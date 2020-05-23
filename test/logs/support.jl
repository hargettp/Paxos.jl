using Paxos.Ballots
using Paxos.Clients
using Paxos.Logs.Common
using Paxos.Nodes

using UUIDs

function logAddEntry(log=Log())
  client = Client()
  req = request(client, Operation(:inc))
  ballot = Ballot(nodeid(), BallotNumber(nextInstance(log), 0), req)
  addEntry(log, LogEntry(req))
  log
end