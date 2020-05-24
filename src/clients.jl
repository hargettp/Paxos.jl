module Clients

export Client, request

using Random
using UUIDs
using ..Ballots
using ..Configurations
using ..Nodes
using ..Transports.Common

mutable struct Client
  id::NodeID
  configuration::Configuration
  requestSequenceNumber::SequenceNumber
  transport;:Transport
  messenger::Union{Messenger,Nothing}
end

# Client(transport::Transport) = Client(nodeid(), 0, transport, nothing)

Ballots.RequestID(client::Client) =
  Ballots.RequestID(uuid4(), client.id, client.requestSequenceNumber += 1)

# Client protocol

"""
Exception thrown when there is no server that can respond to a client request
"""
struct NoAvailableServerException <: Exception end

function request(client::Client, timeout, command::Command)
  req = Request(RequestID(client), command)
  for address in shuffle(memberAddresses(client.configuration))
    if client.messenger === nothing
      try
        client.messenger = connectTo(client.transport, address)
      catch ex
        @error "Error connecting to server" exception = (ex, stacktrace(catch_backtrace()))
        # let's try the next address
        continue
      end
    end
    try
      return call(client.messenger, timeout, req)
    catch ex
      @error "Error making request of server" exception = (ex, stacktrace(catch_backtrace()))
      close(client.messenger)
      client.messenger = nothing
    end
  end
  # if we wind up here, we couldn't contact any server reliably
  throw(NoAvailableServerException())
end


end
