module Clients

export Client, requestID, request

using UUIDs
using ..Ballots
using ..Nodes

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

request(client::Client,op::Operation) = Request(requestID(client), op)

end