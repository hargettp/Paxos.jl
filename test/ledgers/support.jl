using Paxos.Ballots
using Paxos.Ledgers
using Paxos.Nodes
using Paxos.Transports.TCP
using Paxos.Transports.Memory

using UUIDs

function ledgerAddEntry(ledger=Ledger())
  req = Request(RequestID(uuid4(),NodeID(),SequenceNumber(1)), Operation(:inc))
  leaderID = NodeID()
  addEntry(ledger, leaderID, req)
  ledger
end