module Leaders

export lead

using Sockets

using ..Ballots
using ..Configurations
using ..Logs.Common
using ..Nodes
using ..Protocols
using ..Transports.Common
using ..Utils

mutable struct Leader
  id::NodeID
  address::String
  log::Log
  requests::Channel
  listener::Union{Listener,Nothing}
end

Leader(id::NodeID, address::String, log::Log) = Leader(id, address, log, Channel(), nothing)

function serve(leader::Leader, transport::Transport) end

function lead(leaderID::NodeID, log::Log, cfg::Configuration, transport::Transport)
  @sync begin
    cluster = Cluster(50, cfg, Connections(transport))
    leader = Leader(leaderID, memberAddress(cfg, leaderID), log)
    server = @async serve(leader, transport)
    try
      while isopen(leader.requests)
        clientRequests = readAvailable(leader.requests)
        clients::Dict{InstanceID,Messenger}, ballots::Vector{Ballot} =
          clientBallots(log, leader.id, clientRequests)
        try
          ballotNumbers = map(ballots) do ballot
            ballot.number
          end
          votes::Vector{Ballot} = prepare(cluster, ballotNumbers)
          # concatenate the returned ballots with the requested,
          # and choose the ballot with highest sequence number in each instance
          choices::Vector{Ballot} = chooseBallots(hcat(ballots, votes))
          promises::Vector{BallotNumber} = propose(cluster, choices)
          acceptances::Vector{BallotNumber} = accept(cluster, promises)
          # # TODO this is only for finding failures
          # requestedBallots = chooseBallots(ballots)
          for acceptance in acceptances
            instanceID = acceptance.instanceID
            respond(clients[instanceID], requestAccepted)
          end
        catch ex
          result = isa(ex, NoQuorumAvailableException) ? noQuorum : requestFailed
          for client in values(clients)
            respond(client, result)
          end
        end
      end
    finally
      close(server)
    end
  end
end


function preparePhase(cluster::Cluster, leader::Leader, ballots::Vector{Ballot}) end

function clientBallots(
  log::Log,
  leaderID::NodeID,
  clientRequests::Vector{Tuple{Messenger,Request}},
)
  clients = Dict{InstanceID,Messenger}()
  ballots = map(clientRequests) do clientRequest
    client, request = clientRequest
    ballot = request!(log, leaderID, request)
    clients[ballot.number.instanceID] = client
    ballot
  end
  clients, ballots
end

"""
Given a collection of ballots, likely for different instances,
choose the ballot with the highest sequence number in each instance
"""
function chooseBallots(ballots::Vector{Ballot})
  chosenBallots = Dict{BallotNumber,Ballot}()
  for ballot in ballots
    instanceID = ballot.number.instanceID
    if haskey(chosenBallots, instanceID)
      chosenBallots[instanceID] = ballot
    else
      # This is <=, because typically `ballots` is a concatenation
      # of both prepared or requested ballots and voted ballots,
      # with voted ballots coming later. Roughly this implements rule B3(B)
      # of Paxos, and the use of equality ensures that if a vote
      # was for the same ballot number that we reuse that "earlier" decree (e.g., `Request`).
      # Of course, if there is a higher ballot, that decree will be used instead
      if chosenBallots[instanceID].number.sequenceNumber < ballot.number.sequenceNumber
        chosenBallots[instanceID] = ballot
      elseif chosenBallots[instanceID].number.sequenceNumber == ballot.number.sequenceNumber
        # the prepared ballot number has already beeb used, so let's
        # reuse the decree of the earlier use but assign a higher ballot number
        chosenBallots[instanceID] = Ballot(ballot)
      end
    end
  end
  chosenBallots
end

function recordChoices(log::Log, ballots::Vector{Ballot})

end

end
