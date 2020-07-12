"""
Data structure useful for tracking the state of one or more instances of the
Paxos algorithm.
"""
module Ledgers

export Ledger,
  LedgerEntryState,
  LedgerEntry,
  entryOpen,
  entryAccepted,
  entryApplied,
  nextInstance,
  addEntry,
  nextBallotNumber!,
  apply!,
  request!,
  votes!,
  prepare!,
  promise!,
  accept!

using ..Ballots
using ..Nodes

"""
`open` - The entry is new, and has not been populated by any ballot activity

`requested` - The entry corresponds to a local request ready to be prepared.

`prepared` - The entry was discovered through an initial `Prepare` phase

`promised`- Once promised, only requests with a higher ballot can replace
the request in the entry

`accepted` - An accepted entry will eventually by accepted by all members of the cluster

`applied` - The underlying command in the entry's request has been applied
to application state
"""
@enum LedgerEntryState begin
  entryOpen
  entryPromised
  entryAccepted
  entryApplied
end

"""
A `LedgerEntry` captures the state of a `Command` to apply to a `Ledger`s external
model or state machine. Conveniently, a ledger entry has a structure suitable
for use as a "ledger" for 1 instance of the Paxos algorithm: as ballots
for that instance progress the entry contains the state needed for a
leader, follower, or learner to move towards an outcome or final ballot
containing the chosen command for application.
"""
mutable struct LedgerEntry
  state::LedgerEntryState
  sequenceNumber::SequenceNumber
  request::Union{Request,Nothing}
end

LedgerEntry(ballot::Ballot) = LedgerEntry(entryOpen, ballot.number.sequenceNumber, ballot.request)

LedgerEntry(request::Request) = LedgerEntry(entryOpen, SequenceNumber(1), request)

LedgerEntry(sequenceNumber::SequenceNumber) = LedgerEntry(entryOpen, sequenceNumber, nothing)

"""
A ledger is a record of `Command`s to apply to an external data structure or
state machine. A ledger is structured as a sequence of `LedgerEntry` objects.
"""
mutable struct Ledger
  """
  The entries in the ledger, accessed by their index. The reason for using
  a `Dict` instead of an array (with a base offset) is to allow for a potentially
  sparse list of entries.
  """
  entries::Dict{InstanceID,LedgerEntry}

  """
  Index of earliest entry in ledger
  """
  earliestIndex::Union{InstanceID,Nothing}
  """
  Index of latest entry in ledger
  """
  latestIndex::Union{InstanceID,Nothing}
  """
  Index of latest applied entry, or nothing if none applied yet
  """
  latestApplied::Union{Integer,Nothing}

  """
  Lock to protect concurrent access to the ledger and its entries
  """
  lock::ReentrantLock
end

Ledger() = Ledger(Dict(), InstanceID(0), nothing, nothing, ReentrantLock())

function withLedger(fn::Function, ledger::Ledger)
  try
    lock(ledger.lock)
    fn(ledger)
  finally
    unlock(ledger.lock)
  end
end

function Base.isempty(ledger::Ledger)
  withLedger(ledger) do ledger
    isempty(ledger.entries)
  end
end

"""
Return true if the ledger is not empty and has unapplied entries, false
otherwise
"""
function Base.isready(ledger::Ledger)
  withLedger(ledger) do ledger
    return if isempty(ledger)
      false
    else
      if ledger.latestApplied == nothing
        false
      else
        (ledger.latestApplied < ledger.latestIndex) && ledger.latestApplied.state == entryAccepted
      end
    end
  end
end

function Base.length(ledger::Ledger)
  length(ledger.entries)
end

"""
Return the next unused instance (actually, the next unused index) in the ledger
"""
function nextInstance(ledger::Ledger)
  withLedger(ledger) do ledger
    (ledger.latestIndex === nothing) ? ledger.earliestIndex : InstanceID(ledger.latestIndex.value + 1)
  end
end

"""
Create a ballot number for an instance
"""
function nextBallotNumber!(ledger::Ledger, leaderID::NodeID, instanceID = nextInstance(ledger))
  withLedger(ledger) do ledger
    entry = ledger.entries[instanceID]
    entry.sequenceNumber += 1
    BallotNumber(instanceID, entry.sequenceNumber, leaderID)
  end
end

function addEntry(ledger::Ledger, entry::LedgerEntry, leaderID::NodeID)
  withLedger(ledger) do ledger
    instanceID = nextInstance(ledger)
    ledger.entries[instanceID] = entry
    ledger.latestIndex = instanceID
    BallotNumber(instanceID, entry.sequenceNumber, leaderID)
  end
end

function apply!(fn::Function, ledger::Ledger, state)
  withLedger(ledger) do ledger
    while isready(ledger)
      nextIndex = (ledger.latestApplied == nothing) ? 0 : (ledger.latestApplied + 1)
      entry = ledger.entries[nextIndex]
      # note we are holding a lock while calling into arbitrary code
      # ....may be worth a rethink
      fn(state, entry.requst.command)
      ledger.latestApplied = nextIndex
    end
  end
end

"""
Given a `Request`, add to the ledger as a new entry (and ballot) in the `entryRequested` state.
Return the resulting `Ballot` created as a result.
"""
function request!(ledger::Ledger, leaderID::NodeID, request::Request)
  withLedger(ledger) do ledger
    entry = LedgerEntry(request)
    ballotNumber = addEntry(ledger, entry, leaderID)
    Ballot(ballotNumber, request)
  end
end

"""
Record choices for each instance in `ballots`
"""
function prepare!(ledger::Ledger, ballots::Dict{InstanceID,Ballot})::Dict{InstanceID,Ballot}
  preparedBallots = Dict{InstanceID,Ballot}()
  withLedger(ledger) do ledger
    for instanceID in ballots
      entry = ledger.entries[instanceID]
      ballot = ballots[instanceID]
      sequenceNumber = ballot.number.sequenceNumber
      if entry.state == entryOpen && entry.sequenceNumber < sequenceNumber
          entry.sequenceNumber = sequenceNumber
          preparedBallots[instanceID] = ballot
      end
    end
  end
  preparedBallots
end

function promise!(ledger::Ledger, promises::Vector{BallotNumber})
  withLedger(ledger) do ledger
    for promise in promises
      instanceID = promise.instanceID
      sequenceNumber = promise.sequenceNumber
      entry = ledger.entries[instanceID]
      if entry.state == entryOpen && entry.sequenceNumber < sequenceNumber
        entry.state = entryPromised
        entry.sequenceNumber = sequenceNumber
      end
    end
  end
end

"""
Compute a ballot number corresponding to the highest sequence number seen
for each instance. This is useful for the "propose" phase of the protocol.
"""
function votes!(ledger::Ledger, ballotNumbers::Vector{BallotNumber})
  withLedger(ledger) do ledger
    map(ballotNumbers) do ballotNumber
      instanceID = ballotNumber.instanceID
      entry = get!(ledger.entries, instanceID, LedgerEntry(ballotNumber.sequenceNumber))
      BallotNumber(instanceID, max(entry.sequenceNumber, ballotNumber.sequenceNumber))
    end
  end
end

function promise!(ledger::Ledger, approved::Dict{InstanceID,BallotNumber})::Dict{InstanceID,BallotNumber}
  promises = Dict{InstanceID,BallotNumber}()
  withLedger(ledger) do ledger
    for instanceID in approved
      ballotNumber = approved[instanceID]
      entry = ledger.entries[instanceID]
      if entry.state == entryOpen && entry.sequenceNumber == ballotNumber.sequenceNumber
        # TODO think about configuration changes
        promises[instanceID] = ballotNumber
      end
    end
  end
  promises
end

function accept!(ledger::Ledger, ballotNumbers::Vector{BallotNumber})
  acceptances = Vector{BallotNumber}()
  withLedger(ledger) do ledger
    accepted = map(ballotNumbers) do ballotNumber
      instanceID = ballotNumber.instanceID
      entry = ledger.entries[instanceID]
      # TOOO hmmm, should we check leader ID who generated the ballot too?
      if entry.state == entryOpen && entry.sequenceNumber == ballotNumber.sequenceNumber
        entry.state = entryAccepted
        push!(acceptances, ballotNumber)
      end
    end
  end
  acceptances
end

end
