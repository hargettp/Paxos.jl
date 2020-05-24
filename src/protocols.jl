module Protocols

using UUIDs

export Cluster, prepare, propose, accept, onPrepare, onPropose, onAccept

# using .Transports
using ..Transports.Common
using ..Ballots
using ..Nodes
using ..Configurations
using ..Logs.Common

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
  connections = connectAll(cluster.connections, memberAddresses(cluster.configuration), cluster.timeout)
  gcall(values(connections),cluster.timeout,msg)
end

# Leader protocol

function prepare(cluster::Cluster, timeout, ballotNumbers::Vector{BallotNumber})
  msg = PrepareMessage(ballotNumbers)
  pcall(cluster,msg)
end

function propose(cluster::Cluster, ballots::Vector{Ballot})
  msg = ProposeMessage(ballots)
  pcall(cluster,msg)
end

function accept(cluster::Cluster, ballotNumbers::Vector{BallotNumber})
  msg = AcceptMessage(ballotNumbers)
  pcall(cluster,msg)
end

# Follower protocol

function onPrepare(log::Log, ballotNumbers::Vector{BallotNumber})
  votes!(log, ballotNumbers)
end

function onPropose(cluster::Cluster, ballots::Vector{Ballot})
  promises!(log, ballots)
end

function onAccept(cluster::Cluster, ballotNumbers::Vector{BallotNumber})
  accepted!(log, ballotNumbers)
end

# Client protocol

function request(cluster::Cluster, command::Command)
end

# Server protocol

function onRequest(cluster::Cluster, command::Command)
end

# Messages

struct PrepareMessage <: Message
  ballotNumbers::Vector{BallotNumber}
end

# Prepare response
struct VoteMessage <: Message
  ballots::Vector{Ballot}
end

struct ProposeMessage <: Message
  ballots::Vector{Ballot}
end

# Propose response
struct PromiseMessage <: Message
  ballotNumbers::Vector{BallotNumber}
end

struct AcceptMessage <: Message
  ballotNumbers::Vector{BallotNumber}
end

# Not required -- accept response
struct AcceptedMessage <: Message
  ballotNumbers::Vector{BallotNumber}
end

struct TimeoutMessage <: Message
end

PaxosMessage = Union{
  PrepareMessage, 
  VoteMessage, 
  ProposeMessage, 
  PromiseMessage,
  AcceptMessage,
  AcceptedMessage,
  TimeoutMessage
  }

struct Connection
  sender::Channel{PaxosMessage}
  receiver::Channel{PaxosMessage}
end

end