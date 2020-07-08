"""
Data types and functions for `Client`s of a Paxos cluster.
"""
module Clients

export Client, invoke

using UUIDs
using ..Ballots
using ..Configurations
using ..Nodes
using ..Protocols
using ..Transports.Common

mutable struct Client
  id::NodeID
  configuration::Configuration
  requestSequenceNumber::SequenceNumber
  transport;:Transport
  messenger::Union{Messenger,Nothing}
end

Ballots.RequestID(client::Client) =
  Ballots.RequestID(uuid4(), client.id, client.requestSequenceNumber += 1)

"""
Invoke the indicated `Commmand`, regulated by consensus to ensure consistent
ordering across all members.
"""
function invoke(client::Client, timeout, command::Command)
  req = Request(RequestID(client), command)
  messenger, response = request(client.transport, client.messenger,memberAddresses(client.configuration),timeout, req)
  client.messenger = messenger
  response
end

end
