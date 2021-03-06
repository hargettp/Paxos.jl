"""
Implementation of the leader side of the Paxos algorithm.
"""
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
        clients, ballots = recordRequests(ledger, leader.id, clientRequests)
        try
          choices = prepareBallots(cluster, ledger, ballots)
          promises = proposeBallots(cluster, ledger, choices)
          acceptances = acceptBallots(cluster, ledger, promises)
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

function recordRequests(
  leader::Leader,
  leaderID::NodeID,
  clientRequests::Vector{Tuple{Messenger,Request}},
)::Tuple{Dict{InstanceID,Messenger},Dict{InstanceID,Ballot}}
  ledger = leader.ledger
  clients = Dict{InstanceID,Messenger}()
  ballots = Dict{InstanceID,Ballot}()
  for clientRequest in clientRequests
    client, request = clientRequest
    ballot = addEntry(ledger, leaderID, request)
    instanceID = ballot.number.instanceID
    clients[instanceID] = client
    ballots[instanceID] = ballot
  end
  clients, ballots
end

"""
Execute the prepare phase, and collect results. For each instance, find the request with the highest
sequence number, and use that request for the instance--or use the one originally assigned by the leader
if no other such request found.
"""
function prepareBallots(
  cluster::Cluster,
  leader::Leader,
  ballots::Dict{InstanceID,Ballot},
)::Dict{InstanceID,Ballot}
  ledger = leader.ledger
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
        chosenBallots[instanceID] = Ballot(ballot.number, maxVote.request)
      end
    end
  end
  prepare!(ledger, chosenBallots)
end

"""
Execute the propose phase, and collect results. For each instance, find the ballot number
chosen in the prepare phase, and then make sure that there was a quorum that voted for that
ballot number. Once found, build a map to associate instance IDs to the approved ballot numbers.
"""
function proposeBallots(
  cluster::Cluster,
  leader::Leader,
  choices::Dict{InstanceID,Ballot},
)::Dict{InstanceID,BallotNumber}
  ledger = leader.ledger
  promises::Vector{Promise} = propose(cluster, collect(values(choices)))
  votes = Dict{InstanceID,Vector{NodeID}}()
  for promise in promises
    memberID = promise.memberID
    for ballotNumber in promise.ballotNumbers
      instanceID = ballotNumber.instanceID
      choice = choices[instanceID].number
      # only include the vote if it matches the leaeder's choice;
      # should simplify quorum verification
      if ballotNumber == choice
        members = get!(votes, instanceID, Vector())
        push!(members, memberID )
      end
    end
  end
  approved = Dict{InstanceID,BallotNumber}()
  for instanceID in keys(votes)
    voters = map(first, votes[instanceID])
    if isquorum(cluster.configuration, Set(voters))
      approved[instanceID] = choices[instanceID].number
    end
  end
  promise!(ledger, approved)
end

function acceptBallots(cluster::Cluster, leader::Leader, promises::Vector{BallotNumber})
  ledger = leader.ledger
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
