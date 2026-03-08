# ScenarioContext: shared state between steps in a scenario

mutable struct ScenarioContext
    data::Dict{Symbol, Any}
end

ScenarioContext() = ScenarioContext(Dict{Symbol, Any}())

Base.getindex(ctx::ScenarioContext, key::Symbol) = ctx.data[key]
Base.setindex!(ctx::ScenarioContext, val, key::Symbol) = (ctx.data[key] = val; val)
Base.getindex(ctx::ScenarioContext, key::AbstractString) = ctx.data[Symbol(key)]
Base.setindex!(ctx::ScenarioContext, val, key::AbstractString) = (ctx.data[Symbol(key)] = val; val)
Base.haskey(ctx::ScenarioContext, key::Symbol) = haskey(ctx.data, key)
Base.haskey(ctx::ScenarioContext, key::AbstractString) = haskey(ctx.data, Symbol(key))
Base.get(ctx::ScenarioContext, key::Symbol, default) = get(ctx.data, key, default)
Base.get(ctx::ScenarioContext, key::AbstractString, default) = get(ctx.data, Symbol(key), default)
