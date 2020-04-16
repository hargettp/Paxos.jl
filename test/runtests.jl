using Paxos

using Test

@testset "Transports" begin

@test typeof(Paxos.Transports.memory()) == Paxos.Transports.MemoryTransport
@test typeof(Paxos.Transports.tcp()) == Paxos.Transports.TCPTransport

end

