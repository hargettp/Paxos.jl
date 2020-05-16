using Paxos.Ballots
using Paxos.Clients
using Paxos.Logs.Common
using Paxos.Nodes

using UUIDs

function logAddEntry(log=Log())
  client = Client()
  req = request(client, Operation(:inc))
  ballot = Ballot(nodeid(), ballotNumber(log),req)
  addEntry(log, logEntry(ballot))
  log
end