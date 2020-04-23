module Common

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
  open
  requested
  prepared
  promised
  accepted
  applied
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
struct Log
  """
  Index of earliest entry in log
  """
  earliestIndex::Int
  """
  Index of latest entry in log
  """
  latestIndex::Int
  """
  Index of latest applied entry, or nothing if none applied yet
  """
  latestApplied::Int
  entries::Dict{Int,LogEntry}
end

Log() = Log(nothing, nothing, nothing,Dict())

function addEntry(log::Log, entry::LogEntry)
  nextIndex = log.latestIndex += 1
  log.entries[nextIndex] = entry
end

end