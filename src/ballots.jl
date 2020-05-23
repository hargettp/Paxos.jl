module Ballots

export Ballot,
    BallotNumber,
    Command,
    InstanceID,
    Operation,
    Request,
    RequestID,
    SequenceNumber

using UUIDs

using ..Nodes
using ..Configurations

"""
An `InstanceID` uniquely names a specific instance of the Paxos algorithm.
Ballots occur within a specific instance, with the ultimate goal of 
choosing a ballot by consensus.

`InstanceID`s are ordered, with "earlier" instances coming before later ones.
The ordering is intended to support ordering instances (and their chosen ballot)
into an ordered log of chosen commands.
"""
InstanceID = UInt128

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
end

struct Ballot
    leaderId::NodeID
    number::BallotNumber
    request::Request
end

end
