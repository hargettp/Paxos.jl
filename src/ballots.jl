module Ballots

export Ballot,
    BallotNumber,
    Command,
    InstanceBallotNumbers,
    InstanceBallots,
    InstanceID,
    Request,
    RequestID,
    SequenceNumber

using UUIDs

using ..Nodes

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

struct Command
    op::Any
end

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

"""
A data structure for containing a sequence of ballots, where
each element in the sequence is a ballot for a specific instance;
successive elements are for successively later instances
"""
InstanceBallots = Dict{BallotNumber,Ballot}

"""
A data structure for containing a sequence of ballot numbers, where
each element in the sequence is a ballot number for a specific instance;
successive elements are for successively later instances
"""
InstanceBallotNumbers = Set{BallotNumber}

end
