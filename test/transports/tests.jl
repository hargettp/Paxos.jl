include("support.jl")

@testset "Transports" begin
    @testset "TCP" begin
        @test typeof(tcp()) == Paxos.Transports.TCP.TCPTransport
        @test testRoundtrip(
            tcp(),
            ("localhost", 8000),
            "hello",
            "Ciao! I heard your greeting",
        )
        @test testBadCalls(tcp())
        @test testGoodCalls(tcp())
    end
    @testset "Memory" begin
        @test typeof(memory()) == Paxos.Transports.Memory.MemoryTransport
        @test testRoundtrip(memory(), "memoryTest1", "hello", "Ciao! I heard your greeting")
        @test testBadCalls(memory())
        @test testGoodCalls(memory())
    end
end
