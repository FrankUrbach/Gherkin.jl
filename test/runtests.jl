using Test
using Gherkin

@testset "Gherkin.jl" begin
    include("test_parser.jl")
    include("test_expressions.jl")
    include("test_tagexpr.jl")
    include("test_executor.jl")
    include("test_tags.jl")
    include("test_junit.jl")
end
