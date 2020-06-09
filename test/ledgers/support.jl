using Paxos.Ballots
using Paxos.Ledgers
using Paxos.Nodes
using Paxos.Transports.Memory

using UUIDs

function ledgerAddEntry(ledger=Ledger())
  req = Request(RequestID(uuid4(),uuid4(),1), Operation(:inc))
  entry = LedgerEntry(req)
  addEntry(ledger, entry)
  ballot = Ballot(nodeid(), BallotNumber(nextInstance(ledger), entry.sequenceNumber), req)
  ledger
end