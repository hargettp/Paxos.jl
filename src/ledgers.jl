module Ledgers

export Ledger,
  LogEntryState,
  LedgerEntry,
  entryOpen,
  entryRequested,
  entryPrepared,
  entryPromised,
  entryAccepted,
  entryApplied,
  nextInstance,
  addEntry,
  nextBallotNumber!,
  apply!,
  request!,
  votes!,
  promises!,
  accepted!

using ...Ballots
using ...Nodes

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
@enum LogEntryState begin
  entryOpen
  entryRequested
  entryPrepared
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
  state::LogEntryState
  sequenceNumber::SequenceNumber
  request::Union{Request,Nothing}
end

LedgerEntry(ballot::Ballot) = LedgerEntry(entryOpen, ballot.number.sequenceNumber, ballot.request)

LedgerEntry(request::Request) = LedgerEntry(entryRequested, 1, request)

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

Ledger() = Ledger(Dict(), 0, nothing, nothing, ReentrantLock())

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
    (ledger.latestIndex === nothing) ? ledger.earliestIndex : (ledger.latestIndex + 1)
  end
end

"""
Create a ballot number for an instance
"""
function nextBallotNumber!(ledger::Ledger, instanceID = nextInstance(ledger))
  withLedger(ledger) do ledger
    entry = ledger.entries[instanceID]
    entry.sequenceNumber += 1
    BallotNumber(instanceID, entry.sequenceNumber)
  end
end

function addEntry(ledger::Ledger, entry::LedgerEntry)
  withLedger(ledger) do ledger
    instanceID = nextInstance(ledger)
    ledger.entries[instanceID] = entry
    ledger.latestIndex = instanceID
    nextBallotNumber!(ledger, instanceID)
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
    ballotNumber = addEntry(ledger, entry)
    Ballot(leaderID, ballotNumber, request)
  end
end

"""
Choose a `Ballot` for a given instance, either choosing the one with the
highest sequence number, or retaining a ballot already chosen.
"""
function prepare!(ledger::Ledger, leaderID::NodeID, vote::Ballot)
  withLedger(ledger) do ledger
    instanceID = vote.number.instanceID
    ledger.latestIndex = max(ledger.latestIndex === nothing ? 0 : ledger.latestIndex, instanceID)
    ledger.earliestIndex =
      min(ledger.earliestIndex === nothing ? 0 : ledger.earliestIndex, instanceID)
    # we expect that we already have an entry, because we previously initiated the request
    entry = ledger.entries[instanceID]
    if entry.state > entryPromised
      # If we've already chosen a decree, then do nothing more
      # this can happen if another leader made it through the algorithm faster
      # with this instance
      nothing
    elseif entry.sequenceNumber <= vote.number.sequenceNumber
      if leaderID == vote.leaderID
        # this was from this leader -- let's use our existing entry
        Ballot(leaderID, BallotNumber(instanceID,entry.sequenceNumber), entry.request)
      else
        # if it wasn't from this leader, then some other leader has already
        # tried this sequence number--so let's go for the next
        # number in preparation for issuing a new ballot, but
        # with the other leader's request
        newSequenceNumber = max(entry.sequenceNumber, vote.number.sequenceNumber) + 1
        # only set the state if we are not already promised
        if entry.state <= entryRequested
          entry.state = entryPrepared
        end
        entry.sequenceNumber = newSequenceNumber
        newBallotNumber = BallotNumber(instanceID, newSequenceNumber)
        newBallot = Ballot(leaderID, newBallotNumber, vote.request)
        newBallot
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

function promises!(ledger::Ledger, ballots::Vector{Ballot})
  withLedger(ledger) do ledger
    promises = map(ballots) do ballot
      instanceID = ballot.number.instanceID
      entry = get!(ledger.entries, instanceID, LedgerEntry(ballot.number.sequenceNumber))
      if (entry.sequenceNumber < ballot.number.sequenceNumber)
        entry.state = entryPromised
        entry.sequenceNumber = ballot.number.sequenceNumber
        # TODO think about configuration changes
        entry.request = ballot.request
        BallotNumber(instanceID, entry.sequenceNumber)
      else
        nothing
      end
    end
    # if we've already seen a sequence number, we won't promise again
    filter(promises) do promise
      promise !== nothing
    end
  end
end

function accepted!(ledger::Ledger, ballotNumbers::Vector{BallotNumber})
  withLedger(ledger) do ledger
    accepted = map(ballotNumbers) do ballotNumber
      instanceID = ballotNumber.instanceID
      entry = get!(ledger.entries, instanceID, LedgerEntry(ballotNumber.sequenceNumber))
      # TOOO hmmm, should we check leader ID who generated the ballot too?
      # TODO if the entry state isn't accepted, we may have missed some messages
      # -- so should we go into a refetch mode?
      if entry.sequenceNumber == ballotNumber.sequenceNumber && entry.state == entryPromised
        entry.state = entryAccepted
        BallotNumber(instanceID, entry.sequenceNumber)
      else
        nothing
      end
    end
    # if we've already seen a sequence number, we won't accept again
    filter(accepted) do acceptance
      acceptance != nothing
    end
  end
end

end
