using Paxos.Ballots
using Paxos.Logs.Common
using Paxos.Nodes
using Paxos.Transports.Memory

using UUIDs

function logAddEntry(log=Log())
  req = Request(RequestID(uuid4(),uuid4(),1), Operation(:inc))
  ballot = Ballot(nodeid(), BallotNumber(nextInstance(log), 0), req)
  addEntry(log, LogEntry(req))
  log
end