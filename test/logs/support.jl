using Paxos.Ballots
using Paxos.Logs.Common
using Paxos.Nodes
using Paxos.Transports.Memory

using UUIDs

function logAddEntry(log=Log())
  req = Request(RequestID(uuid4(),uuid4(),1), Operation(:inc))
  entry = LogEntry(req)
  addEntry(log, entry)
  ballot = Ballot(nodeid(), BallotNumber(nextInstance(log), entry.sequenceNumber), req)
  log
end