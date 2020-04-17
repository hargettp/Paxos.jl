using Paxos
using Paxos.Transports
using Paxos.Utils

using Logging

using Test

function testRoundtrip(transport, greeting, response)
    worked = false
    @debug "Creating listener"
    listenerTask = listener(transport, "test1") do messenger
        for message in receivedMessages(messenger)
            sendMessage(messenger, "$response: $message")
        end
    end
    try
        @debug "Listener created"
        @debug "Connecting"
        connection(transport, "test1") do messenger
            @debug "Connected"
            @debug "Sending test message"
            sendMessage(messenger, greeting)
            @debug "Sent"
            answer = take!(receivedMessages(messenger))
            worked = (answer == "$response: $greeting")
        end
    catch ex
        worked = false
        printError("Error trying to listen", ex)
    finally
        finallyClose(listenerTask)
        finallyClose(connection)
    end
    worked
end

@testset "Transports" begin

    @test typeof(memory()) == Paxos.Transports.MemoryTransport
    @test typeof(tcp()) == Paxos.Transports.TCPTransport

    @test testRoundtrip(memory(), "hello", "Ciao! I heard your greeting")

end
