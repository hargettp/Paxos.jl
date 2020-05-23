module Leaders

export lead

using Sockets

using ..Configurations
using ..Nodes
using ..Transports.Common
using ..Utils
using ..Protocols

mutable struct Leader
  id::NodeID
  address::String
  requests::Channel
  listener::Union{Listener,Nothing}
end

Leader(id::NodeID,address::String) = Leader(id, address, Channel(), nothing)

Leader(id, address) = Leader(id, address, Channel(), nothing)

function serve(leader::Leader, transport::Transport) end

function lead(leaderID::NodeID, cfg::Configuration, transport::Transport)
  @sync begin
    connections = Connections(transport)
    leader = Leader(leaderID, memberAddress(cfg,leaderID))
    server = @async serve(leader, transport)
    try
      while isopen(leader.requests)
        requests = readAvailable(leader.requests)
        
      end
    finally
      close(server)
    end
  end
end

end
