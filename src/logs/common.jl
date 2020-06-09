module Common

export Log,
  LogEntryState,
  LogEntry,
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
A `LogEntry` captures the state of a `Command` to apply to a `Log`s external
model or state machine. Conveniently, a log entry has a structure suitable
for use as a "ledger" for 1 instance of the Paxos algorithm: as ballots
for that instance progress the entry contains the state needed for a
leader, follower, or learner to move towards an outcome or final ballot
containing the chosen command for application.
"""
mutable struct LogEntry
  state::LogEntryState
  sequenceNumber::SequenceNumber
  request::Union{Request,Nothing}
end

LogEntry(ballot::Ballot) = LogEntry(entryOpen, ballot.number.sequenceNumber, ballot.request)

LogEntry(request::Request) = LogEntry(entryRequested, 1, request)

LogEntry(sequenceNumber::SequenceNumber) = LogEntry(entryOpen, sequenceNumber, nothing)

"""
A log is a record of `Command`s to apply to an external data structure or
state machine. A log is structured as a sequence of `LogEntry` objects.
"""
mutable struct Log
  """
  The entries in the log, accessed by their index. The reason for using
  a `Dict` instead of an array (with a base offset) is to allow for a potentially
  sparse list of entries.
  """
  entries::Dict{InstanceID,LogEntry}

  """
  Index of earliest entry in log
  """
  earliestIndex::Union{InstanceID,Nothing}
  """
  Index of latest entry in log
  """
  latestIndex::Union{InstanceID,Nothing}
  """
  Index of latest applied entry, or nothing if none applied yet
  """
  latestApplied::Union{Integer,Nothing}

  """
  Lock to protect concurrent access to the log and its entries
  """
  lock::ReentrantLock
end

Log() = Log(Dict(), 0, nothing, nothing, ReentrantLock())

function withLog(fn::Function, log::Log)
  try
    lock(log.lock)
    fn(log)
  finally
    unlock(log.lock)
  end
end

function Base.isempty(log::Log)
  withLog(log) do log
    isempty(log.entries)
  end
end

"""
Return true if the log is not empty and has unapplied entries, false
otherwise
"""
function Base.isready(log::Log)
  withLog(log) do log
    return if isempty(log)
      false
    else
      if log.latestApplied == nothing
        false
      else
        (log.latestApplied < log.latestIndex) && log.latestApplied.state == entryAccepted
      end
    end
  end
end

function Base.length(log::Log)
  length(log.entries)
end

"""
Return the next unused instance (actually, the next unused index) in the log
"""
function nextInstance(log::Log)
  withLog(log) do log
    (log.latestIndex === nothing) ? log.earliestIndex : (log.latestIndex + 1)
  end
end

"""
Create a ballot number for an instance
"""
function nextBallotNumber!(log::Log, instanceID = nextInstance(log))
  withLog(log) do log
    entry = log.entries[instanceID]
    entry.sequenceNumber += 1
    BallotNumber(instanceID, entry.sequenceNumber)
  end
end

function addEntry(log::Log, entry::LogEntry)
  withLog(log) do log
    instanceID = nextInstance(log)
    log.entries[instanceID] = entry
    log.latestIndex = instanceID
    nextBallotNumber!(log, instanceID)
  end
end

function apply!(fn::Function, log::Log, state)
  withLog(log) do log
    while isready(log)
      nextIndex = (log.latestApplied == nothing) ? 0 : (log.latestApplied + 1)
      entry = log.entries[nextIndex]
      # note we are holding a lock while calling into arbitrary code
      # ....may be worth a rethink
      fn(state, entry.requst.command)
      log.latestApplied = nextIndex
    end
  end
end

"""
Given a `Request`, add to the log as a new entry (and ballot) in the `entryRequested` state.
Return the resulting `Ballot` created as a result.
"""
function request!(log::Log, leaderID::NodeID, request::Request)
  withLog(log) do log
    entry = LogEntry(request)
    ballotNumber = addEntry(log, entry)
    Ballot(leaderID, ballotNumber, request)
  end
end

"""
Choose a `Ballot` for a given instance, either choosing the one with the
highest sequence number, or retaining a ballot already chosen.
"""
function prepare!(log::Log, leaderID::NodeID, vote::Ballot)
  withLog(log) do log
    instanceID = vote.number.instanceID
    log.latestIndex = max(log.latestIndex === nothing ? 0 : log.latestIndex, instanceID)
    log.earliestIndex =
      min(log.earliestIndex === nothing ? 0 : log.earliestIndex, instanceID)
    # we expect that we already have an entry, because we previously initiated the request
    entry = log.entries[instanceID]
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
function votes!(log::Log, ballotNumbers::Vector{BallotNumber})
  withLog(log) do log
    map(ballotNumbers) do ballotNumber
      instanceID = ballotNumber.instanceID
      entry = get!(log.entries, instanceID, LogEntry(ballotNumber.sequenceNumber))
      BallotNumber(instanceID, max(entry.sequenceNumber, ballotNumber.sequenceNumber))
    end
  end
end

function promises!(log::Log, ballots::Vector{Ballot})
  withLog(log) do log
    promises = map(ballots) do ballot
      instanceID = ballot.number.instanceID
      entry = get!(log.entries, instanceID, LogEntry(ballot.number.sequenceNumber))
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

function accepted!(log::Log, ballotNumbers::Vector{BallotNumber})
  withLog(log) do log
    accepted = map(ballotNumbers) do ballotNumber
      instanceID = ballotNumber.instanceID
      entry = get!(log.entries, instanceID, LogEntry(ballotNumber.sequenceNumber))
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
