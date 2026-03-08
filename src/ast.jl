# AST types for Gherkin features

@enum StepKeyword GivenKeyword WhenKeyword ThenKeyword AndKeyword ButKeyword StarKeyword

struct DocString
    content_type::String   # e.g. "json", "", "typeql"
    content::String
end

const DataTable = Vector{Vector{String}}

struct Step
    keyword::StepKeyword
    text::String
    docstring::Union{DocString, Nothing}
    datatable::Union{DataTable, Nothing}
    line::Int
end

struct Tag
    name::String   # without the @ sign
end

struct Background
    description::String
    steps::Vector{Step}
    line::Int
end

struct Scenario
    name::String
    description::String
    tags::Vector{Tag}
    steps::Vector{Step}
    line::Int
end

struct Examples
    name::String
    tags::Vector{Tag}
    header::Vector{String}
    rows::Vector{Vector{String}}
    line::Int
end

struct ScenarioOutline
    name::String
    description::String
    tags::Vector{Tag}
    steps::Vector{Step}
    examples::Vector{Examples}
    line::Int
end

const AbstractScenario = Union{Scenario, ScenarioOutline}

# ─── Rule (Gherkin 6) ─────────────────────────────────────────────────────────

"""
A `Rule:` block groups scenarios within a feature and may have its own
`Background:` that runs after the Feature-level background.
"""
struct Rule
    name::String
    description::String
    tags::Vector{Tag}
    background::Union{Background, Nothing}
    scenarios::Vector{AbstractScenario}
    line::Int
end

"""Union of all direct children a Feature can contain."""
const FeatureChild = Union{AbstractScenario, Rule}

# ─── Feature ──────────────────────────────────────────────────────────────────

struct Feature
    uri::String
    name::String
    description::String
    tags::Vector{Tag}
    background::Union{Background, Nothing}
    children::Vector{FeatureChild}        # top-level scenarios and/or Rules
    line::Int
end

"""
Intercept `feature.scenarios` for backward compatibility.
Returns the flattened list of all concrete scenarios (same as `all_scenarios`).
All other fields fall through to the struct normally.
"""
function Base.getproperty(f::Feature, name::Symbol)
    name === :scenarios && return all_scenarios(f)
    return getfield(f, name)
end

# ─── Helper functions ─────────────────────────────────────────────────────────

"""
    top_level_scenarios(feature) :: Vector{AbstractScenario}

Return only `AbstractScenario` children directly under the Feature
(i.e. NOT inside any `Rule`).
"""
function top_level_scenarios(feature::Feature) :: Vector{AbstractScenario}
    return AbstractScenario[c for c in feature.children if c isa AbstractScenario]
end

"""
    all_scenarios(feature) :: Vector{AbstractScenario}

Return every `AbstractScenario` in the Feature, flattening `Rule` blocks.
"""
function all_scenarios(feature::Feature) :: Vector{AbstractScenario}
    result = AbstractScenario[]
    for child in feature.children
        if child isa AbstractScenario
            push!(result, child)
        elseif child isa Rule
            append!(result, child.scenarios)
        end
    end
    return result
end
