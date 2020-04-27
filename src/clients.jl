module Clients

export Client, requestID, request

using UUIDs
using ..Ballots

mutable struct Client
  id::NodeID
  requestSequenceNumber::SequenceNumber
end

Client() = Client(nodeid(), 0)

function requestID(client::Client)
  RequestID(
    uuid4(),
    client.id,
    client.requestSequenceNumber += 1
    )
end

function request(client::Client,command::Command)
  Request(requestID(client), command)
end

end