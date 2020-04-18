using Paxos
using Paxos.Transports
using Paxos.Utils

using Logging

using Test

function greetingResponder(greeting, response, messenger)
    for message in receivedMessages(messenger)
        sendMessage(messenger, "$response: $message")
    end
end

function testRoundtrip(transport, address, greeting, response)
    bounded(5) do
        worked = false
        @debug "Creating listener"
        listenerTask = listener(transport, address) do messenger
            greetingResponder(greeting, response, messenger)
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
            @error "Error during roundtrip" exception = (ex, stacktrace(catch_backtrace()))
        finally
            finallyClose(listenerTask)
            finallyClose(connection)
        end
        worked
    end
end

function calls(fn, transport, addressesAndtimeouts, overallTimeout, greeting)
    bounded(overallTimeout) do
        listenerTasks = []
        messengers = Array{Messenger, 1}()
        nextResponse = 1
        try
            for addressAndTimeout in addressesAndtimeouts
                address, timeout = addressAndTimeout
                response = nextResponse
                nextResponse += 1
                listenerTask = listener(transport, address) do messenger
                    sleep(timeout)
                    greetingResponder(greeting, response, messenger)
                end
                push!(listenerTasks, listenerTask)
                sleep(0.5)
                messenger = messengerTo(transport, address)
                push!(messengers, messenger)
            end
            responses = call(messengers, overallTimeout, greeting)
            fn(responses)
        catch ex
            @error "Exception caught making calls" exception=(ex, stacktrace(catch_backtrace()))
            rethrow()
        finally
            closeAll(listenerTasks)
            closeAll(messengers)
        end
    end
end

function testGoodCalls(transport)
    worked = false
    addressesAndTimeouts = [
        (("localhost", 8001),1),
        (("localhost", 8002),1),
        (("localhost", 8003),1)
    ]
    calls(transport, addressesAndTimeouts, 3, "hello") do responses
        expected = [
            "1: hello",
            "2: hello",
            "3: hello"
        ]
        @info "Responses are $responses"
        worked = (sort(responses) == expected)
    end
    worked
end

function testBadCalls(transport)
    worked = false
    addressesAndTimeouts = [
        (("localhost", 8001),0.1),
        (("localhost", 8002),2),
        (("localhost", 8003),0.1)
    ]
    calls(transport, addressesAndTimeouts, 2, "hello") do responses
        expected = [
            "1: hello",
            "3: hello"
        ]
        @info "Responses are $responses"
        worked = (sort(responses) == expected)
    end
    worked
end

@testset "Transports" begin
    @testset "Memory" begin
        @test typeof(memory()) == Paxos.Transports.MemoryTransport
        @test testRoundtrip(memory(), "memoryTest1", "hello", "Ciao! I heard your greeting")
        @test testGoodCalls(memory())
        @test testBadCalls(memory())
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
