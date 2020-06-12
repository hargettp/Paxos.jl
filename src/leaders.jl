module Leaders

export lead

using Sockets

using ..Ballots
using ..Configurations
using ..Ledgers
using ..Nodes
using ..Protocols
using ..Transports.Common
using ..Utils

mutable struct Leader
  id::NodeID
  address::String
  ledger::Ledger
  requests::Channel
  listener::Union{Listener,Nothing}
end

Leader(id::NodeID, address::String, ledger::Ledger) =
  Leader(id, address, ledger, Channel(), nothing)

function serve(leader::Leader, transport::Transport) end

function lead(leaderID::NodeID, ledger::Ledger, cfg::Configuration, transport::Transport)
  @sync begin
    cluster = Cluster(50, cfg, Connections(transport))
    leader = Leader(leaderID, memberAddress(cfg, leaderID), ledger)
    server = @async serve(leader, transport)
    try
      while isopen(leader.requests)
        clientRequests = readAvailable(leader.requests)
        clients::Dict{InstanceID,Messenger}, ballots::Dict{InstanceID,Ballot} =
          clientBallots(ledger, leader.id, clientRequests)
        try
          choices::Dict{InstanceID,Ballot} = prepareRequests(cluster, ledger, ballots)
          promises::Vector{BallotNumber} = proposeBallots(cluster, ledger, choices)
          acceptances::Vector{BallotNumber} = acceptBallots(cluster, ledger, promises)
          reportResults(clients, ballots, choices, acceptances)
        catch ex
          result =
            isa(ex, NoQuorumAvailableException) ? Result.noQuorum : Result.requestFailed
          reportFailures(clients, ballots, result)
        end
      end
    finally
      close(server)
    end
  end
end

function clientBallots(
  ledger::Ledger,
  leaderID::NodeID,
  clientRequests::Vector{Tuple{Messenger,Request}},
)::Tuple{Dict{InstanceID,Messenger},Dict{InstanceID,Ballot}}
  clients = Dict{InstanceID,Messenger}()
  ballots = Dict{InstanceID,Ballot}()
  for clientRequest in clientRequests
    client, request = clientRequest
    ballot = request!(ledger, leaderID, request)
    instanceID = ballot.number.instanceID
    clients[instanceID] = client
    ballots[instanceID] = ballot
  end
  clients, ballots
end

function prepareRequests(
  cluster::Cluster,
  ledger::Ledger,
  ballots::Dict{InstanceID,Ballot},
)::Dict{InstanceID,Ballot}
  ballotNumbers = map(values(ballots)) do ballot
    ballot.number
  end
  votes::Vector{Ballot} = prepare(cluster, ballotNumbers)
  # concatenate the returned ballots with the requested,
  # and choose the ballot with highest sequence number in each instance
  votesByInstance = groupBy(votes) do ballot
    ballot.number.instanceID
  end
  chosenBallots = Dict{InstanceID,Ballot}()
  for instanceID in keys(ballots)
    ballot = ballots[instanceID]
    votes = votesByInstance[instanceID]
    maxVote = maxBy(votes) do vote
      vote.number.sequenceNumber
    end
    if maxVote === nothing
      # great, we get to use our request!
      chosenBallots[instanceID] = ballot
    else
      # TODO if we see any vote with an equal or higher number, then odds
      # are good that the leader has fallen behind. Ultimately, ballots shouldn't
      # succeed, but may need a "catchup" procedure if falls too far behind
      # and can't fulfill enough client requests
      if maxVote.number.sequenceNumber < ballot.number.sequenceNumber
        # we have to use the decree from the earlier, highest vote
        chosenBallots[instanceID] = Ballot(ballot.leaderID, ballot.number, maxVote.request)
      end
    end
  end
  prepare!(ledger, chosenBallots)
end

"""
Execute the propose phase, and collect results. For each instance, find the sequence number
chosen by the most members, and then make sure that there was a quorum that voted for that
sequence number. Once found, build a map to associate instance IDs to the chosen ballot number.
"""
function proposeBallots(
  cluster::Cluster,
  ledger::Ledger,
  choices::Dict{InstanceID,Ballot},
)::Dict{InstanceID,BallotNumber}
  promises::Vector{Promise} = propose(cluster, collect(values(choices)))
  function groupPromisesBySequenceNumber(promises::Vector{Promise})
    groupBy(promises) do promise
      promise.ballotNumber.sequenceNumber
    end
  end
  votes::Dict{InstanceID,Dict{SequenceNumber,Vector{Promise}}} =
    groupBy(promises, groupPromisesBySequenceNumber) do promise
      promise.BallotNumber.instanceID
    end
  approved = Dict{InstanceID,BallotNumber}()
  for instanceID in votes
    promises = votes[instanceID]
    sequenceNumbers = collect(keys(promises))
    chosenSequenceNumber = maxBy(sequenceNumbers) do sequenceNumber
      length(promises[sequenceNumber])
    end
    votes = promises[chosenSequenceNumber]
    voters = map(votes) do vote
      vote.memberID
    end
    if isquorum(cluster.configuration, Set(voters))
      approved[instanceID] = BallotNumber(instanceID, chosenSequenceNumber)
    end
  end
  promise!(ledger, approved)
end

function acceptBallots(cluster::Cluster, ledger::Ledger, promises::Vector{BallotNumber})
  acceptances = accept(cluster, promises)
  accept!(ledger, acceptances)
end

function reportResults(
  clients::Dict{InstanceID,Messenger},
  ballots::Dict{InstanceID,Ballot},
  choices::Dict{InstanceID,Ballot},
  acceptances::Vector{BallotNumber},
)
  for acceptance in acceptances
    instanceID = acceptance.instanceID
    acceptedRequestID = choices[instanceID].request.id
    requestID = ballots[instanceID].request.id
    if acceptedRequestID == requestID
      respond(clients[instanceID], requestID, instanceID, Result.requestAccepted)
    else
      respond(clients[instanceID], requestID, instanceID, Result.requestObsolete)
    end
    # let's clear out the client--we've responded
    delete!(clients, instanceID)
  end
  # any clients left...tell them they are obsolete
  for instanceID in keys(clients)
    client = clients[instanceID]
    requestID = ballots[instanceID].request.id
    respond(client, requestID, instanceID, Result.requestObsolete)
  end

end

function reportFailures(
  clients::Dict{InstanceID,Messenger},
  ballots::Dict{InstanceID,Ballot},
  result::Result,
)
  for instanceID in keys(clients)
    client = clients[instanceID]
    requestID = ballots[instanceID].request.id
    respond(client, requestID, instanceID, result)
  end
end

end
