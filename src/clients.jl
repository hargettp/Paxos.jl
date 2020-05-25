module Clients

export Client, request

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

function request(client::Client, timeout, command::Command)
  req = Request(RequestID(client), command)
  return callAny(client.transport, client.messenger,memberAddresses(client.configuration),timeout, req)
end

end
