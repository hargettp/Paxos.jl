using UUIDs

export memory

struct MemoryTransport <: Transport
    listeners::Dict{Any,Channel}
end

struct MemoryConnection <: Connection
    sent::Channel
    received::Channel
end

"""
Create a new transport for passing messages within 
"""
function memory()
    MemoryTransport(Dict())
end

# -----------------

function connectTo(transport::MemoryTransport, recipient)
    listener = transport.listeners.get!(recipient, Channel())
    sent = Channel()
    received = Channel()
    # put the channels in the reverse order of thow the client sees them,
    # because when the serer sends it just writes to the received of the client,
    # and vice versa for client sending to server
    listener.put!(MemoryConnection(received, sent))
    MemoryConnection(sent, received)
end

function listenOn(handler::Function, transport::MemoryTransport, address)
    @sync try
        connections = transport.listeners.get!(address, Channel())
        while true
            client = take!(connections)
            @async handler(client)
        end
    finally
        delete!(transport.listeners, address)
    end
end

function sendTo(connection::MemoryConnection, message)
    put!(connection.sent, message)
end

function receiveFrom(connection::MemoryConnection)
    take!(connection.received)
end

function close(connection::MemoryConnection)
    close(connection.sent)
    close(connection.received)
end
