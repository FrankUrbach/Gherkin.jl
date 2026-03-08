# AST types for Gherkin features

@enum StepKeyword GivenKeyword WhenKeyword ThenKeyword AndKeyword ButKeyword

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

struct Feature
    uri::String             # file path
    name::String
    description::String
    tags::Vector{Tag}
    background::Union{Background, Nothing}
    scenarios::Vector{AbstractScenario}
    line::Int
end
