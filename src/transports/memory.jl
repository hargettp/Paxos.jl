module Memory

export memory

using UUIDs
using Base

using ..Common

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

function Common.connectTo(transport::MemoryTransport, recipient)
    backlog = get!(transport.listeners,recipient, Channel())
    sent = Channel()
    received = Channel()
    # put the channels in the reverse order of thow the client sees them,
    # because when the serer sends it just writes to the received of the client,
    # and vice versa for client sending to server
    put!(backlog,MemoryConnection(received, sent))
    MemoryConnection(sent, received)
end

function Common.listenOn(handler::Function, transport::MemoryTransport, address)
    @sync try
        @debug "Beginning to listen for memory connections on $address"
        connections = get!(transport.listeners,address, Channel())
        while true
            client = take!(connections)
            @async handler(client)
        end
    finally
        delete!(transport.listeners, address)
        @debug "Finished listening for memory connections on $address"
    end
end

function Common.sendTo(connection::MemoryConnection, message)
    put!(connection.sent, message)
end

function Common.receiveFrom(connection::MemoryConnection)
    take!(connection.received)
end

function Base.close(connection::MemoryConnection)
    close(connection.sent)
    close(connection.received)
end

end