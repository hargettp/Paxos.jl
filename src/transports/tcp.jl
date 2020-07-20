"""
Implementation of `Paxos.Transports.Common.Transport` for TCP-based communication
between participants.
"""
module TCP

export tcp

import Sockets

using Serialization

using ..Common
using ...Utils

struct TCPTransport <: Transport
end

struct TCPConnection <: Connection
    socket::Sockets.TCPSocket
end

function tcp()
    TCPTransport()
end

# ----------------

"""
Create a connection (if one is possible) that enables sending and receiving
messages to the recipient. The provided handler should take 1 argument,
a `Connection` for sending or receiving messages with the recipient.
"""
function Common.connectTo(transport::TCPTransport, recipient)
    host, port = recipient
    @debug "Connecting to $recipient over TCP"
    TCPConnection(Sockets.connect(host, port))
end

"""
Listen for incoming connections and invoke the indicated function when they appear.
Returns a `Listener`
"""
function Common.listenOn(handler::Function, transport::TCPTransport, address)
    @debug "Beginning to listen for TCP connections on $address"
    host, port = address
    @sync try
        server = Sockets.listen(port)
        @debug "Waiting for TCP connections"
        while true
            client = Sockets.accept(server)
            @async handler(TCPConnection(client))
        end
        @debug "Finished waiting for TCP connections"
    finally
        close(server)
       @debug "Finished listening for TCP connections on $address"
    end
end

"""
Send a message on the indicated connection, using the specified Transport
"""
function Common.sendTo(connection::TCPConnection, message)
    serialize(connection.socket, message)
end

"""
Receive a message over the indicated connection
"""
function Common.receiveFrom(connection::TCPConnection)
    try
        deserialize(connection.socket)
    catch ex
        if isa(ex, EOFError)
            @debug "Connection closed"
        else
            rethrow()
        end
    end
end

end