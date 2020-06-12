module Protocols

using UUIDs

export Cluster,
  prepare,
  propose,
  accept,
  onPrepare,
  onPropose,
  onAccept,
  request,
  onRequest,
  respond,
  Result,
  requestAccepted,
  requestFailed,
  requestObsolete,
  noQuorum

# using .Transports
using ..Ballots
using ..Configurations
using ..Ledgers
using ..Nodes
using ..Transports.Common
using ..Utils

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
  # """
  # The request was accepted by a quorum
  # """
  requestAccepted
  # """
  # The request was not accepted, but was instead made
  # obsolete by choice of a different request by the quorum.
  # Obsolete requests can be considered for re-execution
  # """
  requestObsolete
  # """
  # An unexpected error occurr during consensus; applications
  # should re-inspect state before retrying the same request
  # """
  requestFailed # only if there is an exception in the protocol
  # """
  # No quorum available to agree on a request
  # """
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

function prepare(cluster::Cluster, ballotNumbers::Vector{BallotNumber})::Vector{Ballot}
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

function propose(cluster::Cluster, ballots::Vector{Ballot})::Vector{BallotNumber}()
  if isempty(ballots)
    Vector{Ballot}()
  else
    msg = ProposeMessage(ballots)
    memberPromises = pcall(cluster, msg)
    promises = Vector{Promise}()
    for memberPromise in memberPromises
      memberID = memberPromise.memberID
      for ballotNumber in memberPromise.ballotNumbers
        push!(promises, Promise(memberID, ballotNumber))
      end
    end
  end
  collect(values(promises))
end

function accept(cluster::Cluster, ballotNumbers::Vector{BallotNumber})::Vector{BallotNumber}
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

function respond(
  client::Messenger,
  requestID::RequestID,
  instanceID::InstanceID,
  result::Result,
)
  msg = ResponseMessage(requestID, instanceID, result)
  sendMessage(client, msg)
end

end
