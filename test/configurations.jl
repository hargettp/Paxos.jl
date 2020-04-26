using Paxos.Ballots
using Paxos.Configurations

@testset CustomTestSet "Configurations" begin

@test isempty(configuration())

@test quorumSize(configuration()) == 1

@test length(addMember(configuration(), nodeid(), "test1").new.members) == 1

@test quorumSize(addMember(configuration(), nodeid(), "test1").new) == 1

@test quorumSize(
  addMember(
    addMember(
      configuration(), 
      nodeid(), 
      "test1"),
    nodeid(), 
    "test2"
    ).new) == 2

@test quorumSize(3) == 2

end