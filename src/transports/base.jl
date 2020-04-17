# export Message,
#     Transport,
#     Connection,
#     connectTo,
#     listenOn,
#     sendTo,
#     receivedMessages,
#     connection,
#     listener

using Logging

using ..Utils

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
    messenger = Messenger(
        connection,
        Channel() do inbound
            messageReceiver(connection, inbound, errors)
        end,
        Channel() do outbound
            messageSender(connection, outbound, errors)
        end,
        errors,
    )
    # sender = @task messageSender
    # # bind(messenger.outbound, sender)
    # receiver = @task messageReceiver
    # # bind(messenger.inbound, receiver)
    # schedule(sender, messenger)
    # schedule(receiver, messenger)
    messenger
end

"""
Continuously receive messages over the connection and places them in the 
messenger's inbound channel, until the messenger is closed.
"""
function messageReceiver(connection::Connection, inbound::Channel, errors::Channel)
    try
        @debug "Preparing to receive messages"
        while true
            try
                # Receive using the connection's transport
                @debug "Receiving message over transport connection: $connection"
                msg = receiveFrom(connection)
                put!(inbound, msg)
                @debug "Message $msg received over transport connection: $connection"
            catch ex
                put!(errors, (missing, ex))
                printError("Error receiving message", ex)
            end
        end
    catch ex
        printError("Error receiving messages", ex)
    finally
        @debug "Finished receive messages"
    end
end

"""
Continously send any messages on the messenger's outbound channel,
until the messenger is closed
"""
function messageSender(connection::Connection, outbound::Channel, errors::Channel)
    try
        @debug "Preparing to deliver messages"
        for msg in outbound
            try
                # Send using the connection's transport
                @debug "Delivering message $msg over transport connection"
                sendTo(connection, msg)
                @debug "Message $msg delivered"
            catch e
                put!(errors, (msg, e))
                printError("Error delivering message", e)
            end
        end
    catch ex
        printError("Error delivering messages", ex)
    finally
        @debug "Finished delivering messages"
    end
end

"""
Enqueue message for sending over the transport connection
"""
function sendMessage(messenger::Messenger, message)
    @debug "Enqueuing message to send"
    put!(messenger.outbound, message)
    @debug "Message enqueued"
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
    conn = connectTo(transport, recipient)
    messenger = Messenger(conn)
    try
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
    @async begin
        @debug "Beginning to listen"
        listenOn(transport, address) do connection
            @debug "Beginning connection handling"
            messenger = Messenger(connection)
            try
                handler(messenger)
            catch ex
                printError("Error while handling", ex)
            finally
                finallyClose(messenger)
                @debug "Finished connection handling"
            end
        end
        @debug "Finished listening"
    end
end

"""
Exception sent to a listener to indicate that it has been closed
"""
struct ListenerClosedException <: Exception end

function Base.close(listener::Listener)
    schedule(listener, ListenerClosedException(), error = true)
end
