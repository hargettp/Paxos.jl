using Paxos.Ballots
using Paxos.Ledgers
using Paxos.Nodes
using Paxos.Transports.TCP
using Paxos.Transports.Memory

using UUIDs

function ledgerAddEntry(ledger=Ledger())
  req = Request(RequestID(uuid4(),uuid4(),1), Operation(:inc))
  leaderID = nodeid()
  entry = LedgerEntry(req)
  addEntry(ledger, entry, leaderID)
  ballot = Ballot(BallotNumber(nextInstance(ledger), entry.sequenceNumber, leaderID), req)
  ledger
end