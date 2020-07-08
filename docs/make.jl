#! /usr/bin/env julia --project --color=yes

using Base.Filesystem

docsDir = abspath(dirname(@__FILE__))
baseDir = abspath(joinpath(docsDir, "../"))

if !in(LOAD_PATH,baseDir)
  push!(LOAD_PATH,baseDir)
end

using Documenter, Paxos

makedocs(
  sitename="Paxos.jl",
  pages = [
    "index.md",
    "Ballots" => "ballots.md",
    "Clients" => "clients.md",
    "Configurations" => "configurations.md",
    "Leaders" => "leaders.md",
    "Ledgers" => "ledgers.md",
    "Nodes" => "nodes.md",
    "Protocols" => "protocols.md",
    "Transports" => [
      "Common Definitions" => "transports_common.md",
      "Memory" => "transports_memory.md",
      "TCP" => "transports_tcp.md"
    ],
    "Utils" => "utils.md"
  ]
  )