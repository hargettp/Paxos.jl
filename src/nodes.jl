"""
Basic types for identifying nodes participating in Paxos
"""
module Nodes

export NodeID, nodeid

using UUIDs

NodeID = UUID

"""
Return a new node ID
"""
nodeid() = uuid4()

end
