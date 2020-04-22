module Common

using ...Types

  """
  `open` - The entry is new, and has not been populated by any ballot activity

  `requested` - The entry corresponds to a local request ready to be proposed.

  `promised`- Once promised, only requests with a higher ballot can replace
  the request in the entry

  `accepted` - An accepted entry will eventually by accepted by all members of the cluster

  `applied` - The underlying command in the entry's request has been applied
  to application state
  """
@enum LogEntryState begin
  open
  promised
  accepted
  applied
end

abstract type AbstractLogEntry end

struct RequestedLogEntry
  ballot::Ballot
end

struct PromisedLogEntry <: AbstractLogEntry
  ballotNumber::BallotNumber
end

struct AcceptedLogEntry <: AbstractLogEntry
  request::Ballot
end

struct AppliedLogEntry
  ballot::Ballot
end

LogEntry = Union{RequestedLogEntry, PromisedLogEntry, AcceptedLogEntry, AppliedLogEntry}

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