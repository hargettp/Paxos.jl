module Common

export Log,
    LogEntryState,
    entryOpen,
    entryRequested,
    entryPrepared,
    entryPromised,
    entryAccepted,
    entryApplied,
    nextInstance,
    addEntry,
    ballotNumber,
    logEntry

using ...Ballots

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
struct LogEntry
    state::LogEntryState
    ballot::Ballot
end

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
    earliestIndex::InstanceID
    """
    Index of latest entry in log
    """
    latestIndex::Union{InstanceID,Nothing}
    """
    Index of latest applied entry, or nothing if none applied yet
    """
    latestApplied::Union{Integer,Nothing}
end

Log() = Log(Dict(), 0, nothing, nothing)

function Base.isempty(log::Log)
    isempty(log.entries)
end

"""
Return true if the log is not empty and has unapplied entries, false
otherwise
"""
function Base.isready(log::Log)
    return if isempty(log)
        false
    else
        if log.latestApplied == nothing
            false
        else
            (log.latestApplied < log.latestIndex) &&
            log.latestApplied.state == entryAccepted
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
  (log.latestIndex == nothing) ? log.earliestIndex : (log.latestIndex + 1)
end

function addEntry(log::Log, entry::LogEntry)
    nextIndex = nextInstance(log)
    log.entries[nextIndex] = entry
    log.latestIndex = nextIndex
end

function apply(fn::Function, log::Log, state)
    while isready(log)
        nextIndex = (log.latestApplied == nothing) ? 0 : (log.latestApplied + 1)
        entry = log.entries[nextIndex]
        fn(state, entry.requst.command)
        log.latestApplied = nextIndex
    end
end

"""
Create a ballot number for an instance
"""
function ballotNumber(log::Log, instanceID=nextInstance(log), sequenceNumber=0)
  BallotNumber(instanceID, sequenceNumber)
end

"""
Create a `LogEntry` for a given `Ballot`
"""
function logEntry(ballot::Ballot, state=entryRequested)
  LogEntry(state, ballot)
end

end
