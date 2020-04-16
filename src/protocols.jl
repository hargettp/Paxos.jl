using .Transports

# Leader protocol

function prepare(transport, cluster::Cluster, request::Request)
end

function propose(transport, cluster::Cluster, request::Request)
end

function accept(transport, cluster::Cluster, request::Request)
end

# Follower protocol

function onPrepare(transport, cluster::Cluster, ballot::Ballot)
end

function onPropose(transport, cluster::Cluster, ballot::Ballot)
end

function onAccept(transport, cluster::Cluster, ballot::Ballot)
end


# Client protocol

function request(transport, cluster::Cluster, command::Command)
end

# Server protocol

function onRequest(transport, cluster::Cluster, command::Command)
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