import Sockets

using Serialization

using ..Utils

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
function connectTo(transport::TCPTransport, recipient)
    host, port = recipient
    @debug "Connecting to $recipient over TCP"
    TCPConnection(Sockets.connect(host, port))
end

"""
Listen for incoming connections and invoke the indicated function when they appear.
Returns a `Listener`
"""
function listenOn(handler::Function, transport::TCPTransport, address)
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
        finallyClose(server)
       @debug "Finished listening for TCP connections on $address"
    end
end

"""
Send a message on the indicated connection, using the specified Transport
"""
function sendTo(connection::TCPConnection, message)
    serialize(connection.socket, message)
end

"""
Receive a message over the indicated connection
"""
function receiveFrom(connection::TCPConnection)
    deserialize(connection.socket)
end
