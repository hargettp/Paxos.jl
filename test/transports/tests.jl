include("support.jl")

tcpAddressesAndTimeouts = [
    (TCPAddress("localhost", 8001),1),
    (TCPAddress("localhost", 8002),1),
    (TCPAddress("localhost", 8003),1)
]

memAddressesAndTimeouts = [
    (MemoryAddress("node1"),1),
    (MemoryAddress("node2"),1),
    (MemoryAddress("node3"),1)
]

@testset CustomTestSet "Transports" begin
    @testset "TCP" begin
        @test typeof(tcp()) == Paxos.Transports.TCP.TCPTransport
        @test testRoundtrip(
            tcp(),
            TCPAddress("localhost", 8000),
            "hello",
            "Ciao! I heard your greeting",
        )
        @test testBadCalls(tcp(), tcpAddressesAndTimeouts)
        @test testGoodCalls(tcp(), tcpAddressesAndTimeouts)
    end
    @testset "Memory" begin
        @test typeof(memory()) == Paxos.Transports.Memory.MemoryTransport
        @test testRoundtrip(memory(), MemoryAddress("memoryTest1"), "hello", "Ciao! I heard your greeting")
        @test testBadCalls(memory(), memAddressesAndTimeouts)
        @test testGoodCalls(memory(), memAddressesAndTimeouts)
    end
end
