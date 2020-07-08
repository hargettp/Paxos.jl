"""
Basic types and functions to support `Ballot`s, a fundamental unit of data exchange
for successful Paxos execution.
"""
module Ballots

export Ballot,
  BallotNumber, Command, InstanceID, Operation, Request, RequestID, SequenceNumber, Promise

using UUIDs

using ..Nodes
using ..Configurations

"""
An `InstanceID` uniquely names a specific instance of the Paxos algorithm.
Ballots occur within a specific instance, with the ultimate goal of 
choosing a ballot by consensus.

`InstanceID`s are ordered, with "earlier" instances coming before later ones.
The ordering is intended to support ordering instances (and their chosen ballot)
into an ordered ledger of chosen commands.
"""
const InstanceID = UInt128

"""
Return `true` if the `left` id refers to an instance that occurs earlier
than the `right`; otherwise, return `false`
"""
function before(left::InstanceID, right::InstanceID)
  left.sequenceNumber < right.sequenceNumber
end

"""
  Return `true` if the left id refers to an instance that occurs later than
  the `right`; otherwise, return true
"""
function after(left, right)
  before(right, left)
end

SequenceNumber = UInt128

struct Operation
  action::Any
end

Command = Union{Operation,Configuration}

struct RequestID
  id::UUID
  clientID::NodeID
  clientSequenceNumber::SequenceNumber
end

struct Request
  id::RequestID
  command::Command
end

struct BallotNumber
  instanceID::InstanceID
  sequenceNumber::SequenceNumber
  leaderID::NodeID
end
BallotNumber(original::BallotNumber) =
  BallotNumber(original.instanceID, original.sequenceNumber + 1, original.leaderID)

struct Ballot
  number::BallotNumber
  request::Request
end

"""
A `Promise` is a message from a member committing to a specific
`Ballot`, and agreeing not to make a similar promise for any ballot
in the same instance but with a lower sequence number.
"""
struct Promise
  memberID::NodeID
  ballotNumber::BallotNumber
end

Ballot(original::Ballot) =
  Ballot(BallotNumber(original.number), original.request)

end
