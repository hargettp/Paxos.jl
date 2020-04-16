export Message, Transport, Connection, connectTo, listenOn, sendTo, receivedMessages, connection, listener

"""
An abstract payload for sending data via a `Transport`
"""
abstract type Message end

"""
A `Transport` delivers messages sent to groups or individual recipients
"""
abstract type Transport end

"""
A `Connection` represents a conduit between a source and a destination: messages may be
sent to the destination from the source, and optionally they may also be received
from the destination to the source. Closing a connection prevents further message exchange
using the connection.
"""
abstract type Connection end

"""
A listener is typically a task that is awaiting incoming connections; closing a listener will
prevent further connections to that listener.
"""
Listener = Task

"""
Close the closeable object, ignoring any exceptions that may result. 
"""
function finallyClose(closeAble)
    try
        close(closeAble)
    catch
        # ignore
    end
end

# -----------------

"""
Create a connection (if one is possible) that enables sending and receiving
messages to the recipient. The provided handler should take 1 argument,
a `Connection` for sending or receiving messages with the recipient.
"""
function connectTo(transport::Transport, recipient) end

"""
Listen for incoming connections and invoke the indicated function when they appear.
Returns a `Listener`. The provided handler should take 1 argument, a `Connection`;
a new handler will be created for each connection accepted by the listener. A listener
"""
function listenOn(handler::Function, transport::Transport, address) end

"""
Send a message on the indicated connection
"""
function sendTo(connection::Connection, message) end

"""
Receive a message over the indicated connection
"""
function receiveFrom(connection::Connection) end

"""
Close the connection, freeing resources associated with it--and stopping any tasks
moving data on the connection.
"""
function Base.close(connection::Connection) end

# -----------------

"""
A messenger handles asynchronous transmission / reception of messages over a `Connection`,
until closed. In addition to stopping the tasks for transmission / reception, closing
the messenger also closes the underlying connection.
"""
struct Messenger{T}
    connection::T
    inbound::Channel
    outbound::Channel
    errors::Channel
end

"""
Construct a messenger for the given resource
"""
function Messenger(connection)
    errors = Channel()
    messenger = Messenger(connection, Channel(), Channel(), errors)
    sender = @task messageSender
    bind(messenger.outbound, sender)
    receiver = @task messageReceiver
    bind(messenger.inbound, receiver)
    schedule(sender, messenger)
    schedule(receiver, messenger)
    messenger
end

"""
Continously send any messages on the messenger's outbound channel,
until the messenger is closed
"""
function messageSender(messenger::Messenger)
    for msg in messenger.outbound
        try
            # Send using the connection's transport
            sendTo(messenger.connection, msg)
        catch e
            put!(messenger.errors, (msg, e))
        end
    end
end

"""
Continuously receive messages over the connection and places them in the 
messenger's inbound channel, until the messenger is closed.
"""
function messageReceiver(messenger::Messenger)
    while true
        try
            # Receive using the connection's transport
            msg = receiveFrom(messenger.connection)
            put!(messenger.inbound, msg)
        catch e
            put!(messenger.errors, (missing, e))
        end
    end
end

"""
Return a channel for processing messages received on the Messenger
"""
function receivedMessages(messenger::Messenger)
    messenger.inbound
end

function Base.close(connection::Messenger)
    finallyClose(connection.resource)
    finallyClose(connection.outbound)
    finallyClose(connection.inbound)
    finallyClose(connection.errors)
end

"""
Create a `Connection` to the recepient and a `Messenger` to exchange messages,
then invoke the handler with the `Messenger` as an argument. Close the messenger
as soon as the connection exits.
"""
function connection(handler::Function, transport::Transport, recipient)
    try
        conn = connectTo(transport, recipient)
        messenger = Messenger(conn)
        handler(messenger)
    finally
        finallyClose(messenger)
    end
end

"""
Create a listener on the underlying transport at the indicated address,
invoking the handler for each `Connection` discveroed. A listner should be `close`d
when no longer needed, to free up resources
"""
function listener(handler::Function, transport::Transport, address)
    @async listenOn(transport, address) do connection
        messenger = Messenger(connection)
        try
            handler(messenger)
        finally
            finallyClose(messenger)
        end
    end
end

"""
Exception sent to a listener to indicate that it has been closed
"""
struct ListenerClosedException <: Exception
end

function Base.close(listener::Listener)
  schedule(listener, ListenerClosedException(),error = true)
end
