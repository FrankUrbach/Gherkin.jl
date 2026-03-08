using Test
using Gherkin

@testset "Gherkin.jl" begin
    include("test_parser.jl")
    include("test_expressions.jl")
    include("test_executor.jl")
end
