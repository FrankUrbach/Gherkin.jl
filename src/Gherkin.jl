module Gherkin

using Test
using Dates

include("ast.jl")
include("expressions.jl")
include("context.jl")
include("registry.jl")
include("reporter.jl")
include("parser.jl")
include("executor.jl")   # defines HookDefinition — must precede macros.jl
include("junit.jl")
include("macros.jl")

# ─── Global registries / hook storage ────────────────────────────────────────

""" Global step registry — step definitions registered via @given/@when/@then. """
const GLOBAL_REGISTRY = StepRegistry()

""" Per-scenario before-hooks (run before each scenario). """
const BEFORE_HOOKS = HookDefinition[]

""" Per-scenario after-hooks (run after each scenario). """
const AFTER_HOOKS  = HookDefinition[]

""" Suite-level setup hook (run once before any scenario). """
const BEFORE_ALL_HOOKS = Function[]

""" Suite-level teardown hook (run once after all scenarios). """
const AFTER_ALL_HOOKS  = Function[]

# ─── Reset helpers ────────────────────────────────────────────────────────────

""" Clear all registered step definitions. """
reset_registry!() = empty!(GLOBAL_REGISTRY.definitions)

""" Clear all registered hooks (before, after, beforeall, afterall). """
function reset_hooks!()
    empty!(BEFORE_HOOKS)
    empty!(AFTER_HOOKS)
    empty!(BEFORE_ALL_HOOKS)
    empty!(AFTER_ALL_HOOKS)
    nothing
end

# ─── Exports ─────────────────────────────────────────────────────────────────

export
    # ── AST types ──────────────────────────────────────────────────────────────
    Feature, Scenario, ScenarioOutline, Background, Step, DocString, DataTable,
    Tag, Examples, AbstractScenario,
    StepKeyword, GivenKeyword, WhenKeyword, ThenKeyword, AndKeyword, ButKeyword,

    # ── Parser ─────────────────────────────────────────────────────────────────
    parse_feature, parse_feature_string,

    # ── Context ────────────────────────────────────────────────────────────────
    ScenarioContext,

    # ── Registry ───────────────────────────────────────────────────────────────
    StepRegistry, StepDefinition, register!, find_step,
    UndefinedStep, AmbiguousStep,
    GLOBAL_REGISTRY, reset_registry!,

    # ── Hook infrastructure ────────────────────────────────────────────────────
    HookDefinition,
    BEFORE_HOOKS, AFTER_HOOKS, BEFORE_ALL_HOOKS, AFTER_ALL_HOOKS,
    reset_hooks!,

    # ── Step / hook macros ─────────────────────────────────────────────────────
    @given, @when, @then, @step, @and, @but,
    @expect,
    @before, @after, @beforeall, @afterall,

    # ── Result types ───────────────────────────────────────────────────────────
    StepResult, ScenarioResult, FeatureResult, RunResults,
    passed,

    # ── Runner ─────────────────────────────────────────────────────────────────
    runspec, run_feature, run_scenario,
    expand_outline, expand_scenarios,

    # ── JUnit XML ──────────────────────────────────────────────────────────────
    write_junit_xml,

    # ── Expressions ────────────────────────────────────────────────────────────
    StepPattern, compile_pattern, match_step

end
