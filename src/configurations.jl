"""
Data types and functions support `Configuration`s, which describe the participants
in a Paxos cluster.
"""
module Configurations

export isquorum,
  quorumSize,
  NoQuorumAvailableException,
  Configuration,
  configuration,
  memberAddress,
  memberAddresses,
  addMember,
  removeMember

using ..Nodes

struct OrdinaryConfiguration
  """
  Dictionary mapping IDs of members to their addresses
  """
  members::Dict{NodeID,Any}
end

"""
A transition configuration (inspired by Raft) supports rollout of a 
new configuration, with potentially differences in membership
"""
struct TransitionConfiguration
  old::OrdinaryConfiguration
  new::OrdinaryConfiguration
end

"""
A configuration is the general type for maintaining a list of menbers
and addreses where they can be reached over transport
"""
Configuration = Union{OrdinaryConfiguration,TransitionConfiguration}

"""
Return the address for the specfied node, or error if no such address
"""
function memberAddress(cfg::OrdinaryConfiguration, memberID::NodeID)
  cfg.members[memberID]
end

function memberAddress(cfg::TransitionConfiguration, memberID::NodeID)
  if haskey(cfg.old, memberID)
    memberAddress(cfg.old, memberID)
  else
    memberAddress(cfg.new, memberID)
  end
end

"""
Return the addresses of all membes in the configuration
"""
function memberAddresses(cfg::OrdinaryConfiguration)
  Set(keys(cfg.members))
end

function memberAddresses(cfg::TransitionConfiguration)
  union(memberAddresses(cfg.old), memberAddresses(cfg.new))
end

"""
Return the minimum size for a majority of members in the configuration
"""
function quorumSize(cfg::OrdinaryConfiguration)
  quorumSize(length(cfg.members))
end

"""
For `Integer` values, return the required number of participants for a majority
"""
function quorumSize(len::Integer)
  convert(Integer, if iseven(len)
    (len / 2) + 1
  else
    ceil(len / 2)
  end)
end

"""
Exception thrown when no quorum is available to respond to Paxos messages
"""
struct NoQuorumAvailableException <: Exception end

"""
Return true if the list of members represents a quorum for the configuration
"""
function isquorum(cfg::OrdinaryConfiguration, members::Set{NodeID})
  count = 0
  for member in members
    if haskey(cfg.members, member)
      count += 1
    end
  end
  count >= quorumSize(cfg)
end

"""
During transitions, eturn true if the list of members represents a quorum in 
both old and new configurations
"""
function isquorum(cfg::TransitionConfiguration, members::Set{NodeID})
  isquorum(cfg.old, members) && isquorum(cfg.new, members)
end

function Base.isempty(cfg::OrdinaryConfiguration)
  isempty(cfg.members)
end

function Base.isempty(cfg::TransitionConfiguration)
  isempty(cfg.old) && isempty(cfg.new)
end

"""
Create a new, empty `OrdinaryConfiguration`
"""
function configuration(members::Dict{NodeID,Any} = Dict{NodeID,Any}())
  OrdinaryConfiguration(members)
end

function addMember(cfg::OrdinaryConfiguration, id::NodeID, address)
  TransitionConfiguration(cfg, configuration(merge(cfg.members, Dict(id => address))))
end

function addMember(cfg::TransitionConfiguration, id::NodeID, address)
  TransitionConfiguration(
    cfg.old,
    configuration(merge(cfg.new.members, Dict(id => address))),
  )
end

function removeMember(cfg::OrdinaryConfiguration, id::NodeID)
  TransitionConfiguration(cfg, configuration(delete!(Dict(cfg.members), id)))
end

function removeMember(cfg::TransitionConfiguration, id::NodeID)
  TransitionConfiguration(cfg, configuration(delete!(Dict(cfg.new.members), id)))
end

end
