module Common

export Message,
    Transport,
    Connection,
    Messenger,
    Listener,
    connectTo,
    messengerTo,
    listenOn,
    sendTo,
    receivedMessages,
    sendMessage,
    connection,
    listener,
    call,
    gcall

using Logging

using ...Utils
using Base

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
    resource::T
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
            # Receive using the connection's transport
            @debug "Receiving message over transport connection: $connection"
            msg = receiveFrom(connection)
            put!(inbound, msg)
            @debug "Message $msg received over transport connection: $connection"
        end
    catch ex
        if isa(ex, InvalidStateException) && (ex.state == :closed)
            @debug "Inbound closed"
        else
            @error "Error receiving messages" exception = (ex, stacktrace(catch_backtrace()))
        end
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
            @debug "Delivering message $msg over transport connection"
            sendTo(connection, msg)
            @debug "Message $msg delivered"
        end
    catch ex
        if (isa(ex, InvalidStateException) && (ex.state == :closed)) ||
                isa(ex, Base.IOError)
            @debug "Outbounbd closed"
        else
            @error "Error delivering messages" exception = (ex, stacktrace(catch_backtrace()))
        end
    finally
        @debug "Finished delivering messages"
    end
end

"""
Enqueue message for sending over the transport connection
"""
function sendMessage(messenger::Messenger, message)
    @debug "Enqueuing message to send"
    try
        put!(messenger.outbound, message)
    catch ex
        if (isa(ex, InvalidStateException) && (ex.state == :closed))
            @debug "Sending channel closed"
        else
            rethrow()
        end
    end
    @debug "Message enqueued"
end

"""
Return a channel for processing messages received on the Messenger
"""
function receivedMessages(messenger::Messenger)
    messenger.inbound
end

function Base.close(connection::Messenger)
    close(connection.resource)
    close(connection.outbound)
    close(connection.inbound)
    close(connection.errors)
end

"""
Connect to the recipient via the underlying transport and construct
a `Messenger` with the resulting `Connection`
"""
function messengerTo(transport, recipient)
    Messenger(connectTo(transport, recipient))
end

"""
Create a `Connection` to the recepient and a `Messenger` to exchange messages,
then invoke the handler with the `Messenger` as an argument. Close the messenger
as soon as the connection exits.
"""
function connection(handler::Function, transport::Transport, recipient)
    @debug "Beginning connection to $recipient"
    try
        messenger = messengerTo(transport, recipient)
        try
            handler(messenger)
        finally
            close(messenger)
        end
    finally
        @debug "Finished connection to $recipient"
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
            @debug "Beginning to handle a connection"
            messenger = Messenger(connection)
            try
                handler(messenger)
            catch ex
                @error "Error while handling" exception =
                    (ex, stacktrace(catch_backtrace()))
            finally
                close(messenger)
                @debug "Finished handling a connection"
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

# -----------------

"""
Send a message through the specified `Messenger`, and wait up to `timeout`
seconds for a response. If no response received in the alloted time, then
throw a `TimeoutException`; otherwise, return the reeived response.
"""
function call(messenger::Messenger, timeout, message)
    bounded(timeout) do
        sendMessage(messenger, message)
        response = take!(receivedMessages(messenger))
        return response
    end
end

"""
Send the message through each of the `Messenger`s, but only allow
`timeout` seconds for a response. Return all results received within
the alloted time, if any.
"""
function gcall(messengers::Vector{Messenger}, timeout, message)
    sz = length(messengers)
    responses = Channel()
    results = Vector()
    try
        bounded(timeout) do
            for messenger in messengers
                @async begin
                    response = call(messenger, timeout, message)
                    put!(responses, response)
                end
            end
            for response in responses
                push!(results, response)
                if length(results) >= sz
                    break
                end
            end
        end
    catch ex
        if !isa(ex, TimeoutException)
            rethrow()
        end
    finally
        Base.close(responses)
    end
    results
end

end