using Paxos
using Paxos.Transports
using Paxos.Utils

using Logging

using Test

function testRoundtrip(transport, address, greeting, response)
    worked = false
    @debug "Creating listener"
    listenerTask = listener(transport, address) do messenger
        for message in receivedMessages(messenger)
            sendMessage(messenger, "$response: $message")
        end
    end
    @debug "Pausing for listener to be alive"
    sleep(2)
    try
        @debug "Listener created"
        @debug "Connecting"
        connection(transport, address) do messenger
            @debug "Connected"
            @debug "Sending test message"
            sendMessage(messenger, greeting)
            @debug "Sent"
            answer = take!(receivedMessages(messenger))
            worked = (answer == "$response: $greeting")
        end
    catch ex
        worked = false
        printError("Error during roundtrip", ex)
    finally
        finallyClose(listenerTask)
        finallyClose(connection)
    end
    worked
end

@testset "Transports" begin
    @testset "Memory" begin
        @test typeof(memory()) == Paxos.Transports.MemoryTransport
        @test testRoundtrip(memory(), "memoryTest1", "hello", "Ciao! I heard your greeting")
    end

    @testset "TCP" begin
        @test typeof(tcp()) == Paxos.Transports.TCPTransport
        @test testRoundtrip(
            tcp(),
            ("localhost", 8000),
            "hello",
            "Ciao! I heard your greeting",
        )
    end
end
