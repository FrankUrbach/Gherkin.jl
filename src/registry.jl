# Step definition registry

struct StepDefinition
    pattern::StepPattern
    fn::Function
    location::String        # "filename:line"
end

mutable struct StepRegistry
    definitions::Vector{StepDefinition}
end

StepRegistry() = StepRegistry(StepDefinition[])

"""
    register!(registry, pattern, fn, location)

Register a step definition with a pattern (String or Regex), a function, and a source location.
"""
function register!(registry::StepRegistry, pattern, fn::Function, location::String)
    push!(registry.definitions, StepDefinition(compile_pattern(pattern), fn, location))
end

# Exceptions
struct UndefinedStep <: Exception
    text::String
end

struct AmbiguousStep <: Exception
    text::String
    locations::Vector{String}
end

Base.showerror(io::IO, e::UndefinedStep) = print(io, "UndefinedStep: No step definition found for: \"$(e.text)\"")
Base.showerror(io::IO, e::AmbiguousStep) = print(io, "AmbiguousStep: Multiple step definitions match \"$(e.text)\": $(join(e.locations, ", "))")

"""
    find_step(registry, text) :: Tuple{StepDefinition, Vector{Any}}

Find a matching step definition for the given step text.
Throws UndefinedStep if none found, AmbiguousStep if multiple match.
"""
function find_step(registry::StepRegistry, text::String) :: Tuple{StepDefinition, Vector{Any}}
    matches = Tuple{StepDefinition, Vector{Any}}[]
    for defn in registry.definitions
        params = match_step(defn.pattern, text)
        if params !== nothing
            push!(matches, (defn, params))
        end
    end
    if isempty(matches)
        throw(UndefinedStep(text))
    elseif length(matches) > 1
        throw(AmbiguousStep(text, [m[1].location for m in matches]))
    end
    return matches[1]
end
