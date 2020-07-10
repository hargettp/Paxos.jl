"""
Basic types for identifying nodes participating in Paxos
"""
module Nodes

export NodeID

using UUIDs

struct NodeID
  value::UUID
end

"""
Return a new node ID
"""
NodeID() = NodeID(uuid4())

end
