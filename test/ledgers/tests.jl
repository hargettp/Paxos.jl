include("./support.jl")

@testset CustomTestSet "Ledgers" begin

  @test isempty(Ledger()) == true
  @test isempty(ledgerAddEntry()) == false
  @test length(ledgerAddEntry()) == 1
  @test ledgerAddEntry().latestApplied == nothing
  
end
