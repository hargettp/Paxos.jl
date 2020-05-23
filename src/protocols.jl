module Protocols

using UUIDs

export Cluster, prepare, propose, accept, onPrepare, onPropose, onAccept

# using .Transports
using ..Transports.Common
using ..Ballots
using ..Nodes
using ..Configurations

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

function prepare(cluster::Cluster, timeout, ballotNumbers::Vector{InstanceBallotNumbers})
  msg = PrepareMessage(ballotNumbers)
  pcall(cluster,msg)
end

function propose(cluster::Cluster, ballots::Vector{InstanceBallots})
  msg = ProposeMessage(ballots)
  pcall(cluster,msg)
end

function accept(cluster::Cluster, ballotNumbers::Vector{InstanceBallotNumbers})
  msg = AcceptMessage(ballotNumbers)
  pcall(cluster,msg)
end

# Follower protocol

function onPrepare(cluster::Cluster, ballotNumbers::Vector{InstanceBallotNumbers})
end

function onPropose(cluster::Cluster, ballots::Vector{InstanceBallots})
end

function onAccept(cluster::Cluster, ballotNumbers::Vector{InstanceBallotNumbers})
end


# Client protocol

function request(cluster::Cluster, command::Command)
end

# Server protocol

function onRequest(cluster::Cluster, command::Command)
end

# Messages

struct PrepareMessage <: Message
  ballotNumbers::InstanceBallotNumbers
end

# Prepare response
struct VoteMessage <: Message
  ballots::InstanceBallots
end

struct ProposeMessage <: Message
  ballots::InstanceBallots
end

# Propose response
struct PromiseMessage <: Message
  ballotNumbers::InstanceBallotNumbers
end

struct AcceptMessage <: Message
  ballotNumbers::InstanceBallotNumbers
end

# Not required -- accept response
struct AcceptedMessage <: Message
  ballotNumbers::InstanceBallotNumbers
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