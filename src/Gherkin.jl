module Gherkin

using Test

include("ast.jl")
include("expressions.jl")
include("context.jl")
include("registry.jl")
include("reporter.jl")
include("parser.jl")
include("executor.jl")
include("macros.jl")

# Global registry — step definitions registered here by macros
const GLOBAL_REGISTRY = StepRegistry()

# Global hook storage
const BEFORE_HOOKS = Function[]
const AFTER_HOOKS  = Function[]

# Reset the global registry (useful between test runs)
reset_registry!() = empty!(GLOBAL_REGISTRY.definitions)

# Reset hooks
reset_hooks!() = (empty!(BEFORE_HOOKS); empty!(AFTER_HOOKS); nothing)

export
    # AST types
    Feature, Scenario, ScenarioOutline, Background, Step, DocString, DataTable, Tag, Examples,
    StepKeyword, GivenKeyword, WhenKeyword, ThenKeyword, AndKeyword, ButKeyword,
    # Parser
    parse_feature, parse_feature_string,
    # Context
    ScenarioContext,
    # Registry
    StepRegistry, StepDefinition, register!, find_step, UndefinedStep, AmbiguousStep,
    GLOBAL_REGISTRY, reset_registry!,
    # Hooks
    BEFORE_HOOKS, AFTER_HOOKS, reset_hooks!,
    # Macros
    @given, @when, @then, @step, @and, @but, @expect, @before, @after,
    # Runner
    runspec, run_feature, run_scenario, expand_outline, expand_scenarios,
    # Expressions
    StepPattern, compile_pattern, match_step

end
