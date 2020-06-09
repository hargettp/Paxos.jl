module Protocols

using UUIDs

export Cluster,
  prepare, propose, accept, onPrepare, onPropose, onAccept, request, onRequest, respond

# using .Transports
using ..Transports.Common
using ..Ballots
using ..Nodes
using ..Configurations
using ..Ledgers

mutable struct Cluster
  timeout::Int
  configuration::Configuration
  connections::Connections
end

"""
Perform a `gcall` against all members of the cluster, creating connections
as needed (and as available), if not already present
"""
function pcall(cluster::Cluster, msg)
  connections =
    connectAll(cluster.connections, memberAddresses(cluster.configuration), cluster.timeout)
  responses = gcall(values(connections), cluster.timeout, msg)
  if !isquorum(cluster.configuration, responders(responses))
    throw(NoQuorumAvailableException())
  end
  responses
end

# Messages

struct PrepareMessage <: Message
  ballotNumbers::Vector{BallotNumber}
end

# Prepare response
struct VoteMessage <: Message
  memberID::NodeID
  ballots::Vector{Ballot}
end

struct ProposeMessage <: Message
  ballots::Vector{Ballot}
end

# Propose response
struct PromiseMessage <: Message
  memberID::NodeID
  ballotNumbers::Vector{BallotNumber}
end

struct AcceptMessage <: Message
  ballotNumbers::Vector{BallotNumber}
end

# Not required -- accept response
struct AcceptedMessage <: Message
  ballotNumbers::Vector{BallotNumber}
end

struct RequestMessage <: Message
  request::Request
end

@enum Result begin
  requestAccepted
  requestObsolete
  requestFailed # only if there is an exception in the protocol
  noQuorum
end
struct ResponseMessage <: Message
  requestID::RequestID
  instanceID::InstanceID
  result::Result
end

struct TimeoutMessage <: Message end

PaxosMessage = Union{
  PrepareMessage,
  VoteMessage,
  ProposeMessage,
  PromiseMessage,
  AcceptMessage,
  AcceptedMessage,
  RequestMessage,
  ResponseMessage,
  TimeoutMessage,
}

function responders(messages)
  Set(map(messages) do message
    message.memberID
  end)
end

struct Connection
  sender::Channel{PaxosMessage}
  receiver::Channel{PaxosMessage}
end

# Leader protocol

function prepare(cluster::Cluster, ballotNumbers::Vector{BallotNumber})
  if isempty(ballotNumbers)
    Vector{Ballot}()
  else
    msg = PrepareMessage(ballotNumbers)
    votes = pcall(cluster, msg)
    hcat(map(votes) do vote::VoteMessage
      vote.ballots
    end...)
  end
end

function propose(cluster::Cluster, ballots::Vector{Ballot})
  if isempty(ballots)
    Vector{Ballot}()
  else
    msg = ProposeMessage(ballots)
    promises = pcall(cluster, msg)
    hcat(map(promises::Vector{PromiseMessage}) do promise::PromiseMessage
      promise.ballotNumbers
    end...)
  end
end

function accept(cluster::Cluster, ballotNumbers::Vector{BallotNumber})
  if isempty(ballotNumbers)
    Vector{BallotNumber}()
  else
    msg = AcceptMessage(ballotNumbers)
    acceptances = pcall(cluster, msg)
    hcat(map(acceptances) do acceptance::Vector{AcceptedMessage}
      acceptance.ballotNumbers
    end...)
  end
end

# Follower protocol

function onPrepare(ledger::Ledger, ballotNumbers::Vector{BallotNumber})
  votes!(ledger, ballotNumbers)
end

function onPropose(cluster::Cluster, ballots::Vector{Ballot})
  promises!(ledger, ballots)
end

function onAccept(cluster::Cluster, ballotNumbers::Vector{BallotNumber})
  accepted!(ledger, ballotNumbers)
end

# Client protocol

function request(
  transport::Transport,
  messenger::Union{Messenger,Nothing},
  addresses,
  timeout,
  request::Request,
)
  return callAny(transport, messenger, addresses, timeout, RequestMessage(request))
end

# Server protocol

function onRequest(cluster::Cluster, command::Command) end

function respond(client::Messenger, ballot::Ballot, result::Result)
  msg = ResponseMessage(ballot.request.id, ballot.number.instanceID, result)
  sendMessage(client, msg)
end

end
