include("./support.jl")

@testset CustomTestSet "Logs" begin

  @test isempty(Log()) == true
  @test isempty(logAddEntry()) == false
  @test length(logAddEntry()) == 1
  @test logAddEntry().latestApplied == nothing
  
end
