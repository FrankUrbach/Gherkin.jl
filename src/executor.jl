# Executor: runs features and scenarios, integrating with Test.jl

"""
    expand_outline(outline::ScenarioOutline) :: Vector{Scenario}

Expand a ScenarioOutline into concrete Scenarios by substituting
example row values into step texts.
"""
function expand_outline(outline::ScenarioOutline) :: Vector{Scenario}
    scenarios = Scenario[]
    for examples in outline.examples
        header = examples.header
        for (row_idx, row) in enumerate(examples.rows)
            # Build substitution map
            subs = Dict{String, String}()
            for (col, val) in zip(header, row)
                subs[col] = val
            end

            # Build scenario name using row values
            row_desc = join(["$(h)=$(v)" for (h, v) in zip(header, row)], ", ")
            name = "$(outline.name) (Example $(row_idx): $(row_desc))"

            # Substitute in steps
            new_steps = Step[]
            for step in outline.steps
                new_text = _substitute(step.text, subs)
                new_docstring = if step.docstring !== nothing
                    DocString(step.docstring.content_type,
                              _substitute(step.docstring.content, subs))
                else
                    nothing
                end
                new_datatable = if step.datatable !== nothing
                    [[_substitute(cell, subs) for cell in row_cells]
                     for row_cells in step.datatable]
                else
                    nothing
                end
                push!(new_steps, Step(step.keyword, new_text, new_docstring, new_datatable, step.line))
            end

            sc = Scenario(name, outline.description, outline.tags, new_steps, outline.line)
            push!(scenarios, sc)
        end
    end
    return scenarios
end

function _substitute(text::String, subs::Dict{String, String}) :: String
    result = text
    for (k, v) in subs
        result = replace(result, "<$(k)>" => v)
    end
    return result
end

"""
    expand_scenarios(feature::Feature) :: Vector{Scenario}

Return all concrete Scenarios from the feature, expanding outlines.
"""
function expand_scenarios(feature::Feature) :: Vector{Scenario}
    result = Scenario[]
    for sc in feature.scenarios
        if sc isa Scenario
            push!(result, sc)
        elseif sc isa ScenarioOutline
            append!(result, expand_outline(sc))
        end
    end
    return result
end

"""
    run_step(step, context, registry) :: Symbol

Execute a single step. Returns :pass, :fail, or :undefined.
"""
function run_step(step::Step, context::ScenarioContext, registry::StepRegistry) :: Symbol
    local defn, params
    try
        defn, params = find_step(registry, step.text)
    catch e
        if e isa UndefinedStep
            report_step_undefined(step)
            Test.@test false
            return :undefined
        end
        report_step_fail(step, e)
        Test.@test false
        return :fail
    end

    try
        if !isempty(step.docstring !== nothing ? [step.docstring] : []) ||
           !isempty(step.datatable !== nothing ? [step.datatable] : [])
            # Pass docstring or datatable as extra arg if present
            extra = step.docstring !== nothing ? step.docstring :
                    step.datatable !== nothing ? step.datatable : nothing
            if extra !== nothing
                defn.fn(context, params..., extra)
            else
                defn.fn(context, params...)
            end
        else
            defn.fn(context, params...)
        end
        report_step_pass(step)
        return :pass
    catch e
        report_step_fail(step, e)
        Test.@test false
        return :fail
    end
end

"""
    run_scenario(scenario, background, registry) :: Bool

Execute a single scenario (with optional background steps first).
Returns true if all steps passed.
"""
function run_scenario(scenario::Scenario, background::Union{Background, Nothing},
                      registry::StepRegistry) :: Bool
    context = ScenarioContext()

    # Run before hooks
    for hook in BEFORE_HOOKS
        try
            hook(context)
        catch e
            @warn "Before hook failed" exception=e
        end
    end

    passed = true

    # Run background steps first
    if background !== nothing
        for step in background.steps
            result = run_step(step, context, registry)
            if result != :pass
                passed = false
                # Skip remaining steps after first failure
                remaining_background = background.steps[findnext(s -> s === step, background.steps, 1)+1:end]
                for skipped in remaining_background
                    report_step_skipped(skipped)
                end
                # Also skip all scenario steps
                for skipped in scenario.steps
                    report_step_skipped(skipped)
                end
                # Run after hooks
                for hook in AFTER_HOOKS
                    try; hook(context); catch e; @warn "After hook failed" exception=e; end
                end
                return false
            end
        end
    end

    # Run scenario steps
    failed = false
    for step in scenario.steps
        if failed
            report_step_skipped(step)
            continue
        end
        result = run_step(step, context, registry)
        if result != :pass
            failed = true
            passed = false
        end
    end

    # Run after hooks
    for hook in AFTER_HOOKS
        try
            hook(context)
        catch e
            @warn "After hook failed" exception=e
        end
    end

    return passed
end

"""
    run_feature(feature, registry) :: Bool

Run all scenarios in a feature, wrapped in Test.jl testsets.
"""
function run_feature(feature::Feature, registry::StepRegistry) :: Bool
    report_feature_start(feature)
    all_scenarios = expand_scenarios(feature)
    passed_count = 0

    Test.@testset "$(feature.name)" begin
        for scenario in all_scenarios
            report_scenario_start(scenario)
            local scenario_passed = Ref(true)
            Test.@testset "$(scenario.name)" begin
                result = run_scenario(scenario, feature.background, registry)
                scenario_passed[] = result
            end
            if scenario_passed[]
                passed_count += 1
            end
            report_scenario_result(scenario, scenario_passed[])
        end
    end

    report_feature_result(feature, passed_count, length(all_scenarios))
    return passed_count == length(all_scenarios)
end

"""
    runspec(; features_dir, steps_dir, tags)

Discover and run all feature files, loading step definitions from steps_dir.
"""
function runspec(;
    features_dir::String = "features",
    steps_dir::String = joinpath("features", "steps"),
    tags::Vector{String} = String[]
)
    # Load step definition files
    if isdir(steps_dir)
        for (root, dirs, files) in walkdir(steps_dir)
            for file in files
                if endswith(file, ".jl")
                    include(joinpath(root, file))
                end
            end
        end
    end

    # Find feature files
    feature_files = String[]
    if isdir(features_dir)
        for (root, dirs, files) in walkdir(features_dir)
            for file in files
                if endswith(file, ".feature")
                    push!(feature_files, joinpath(root, file))
                end
            end
        end
    end

    sort!(feature_files)

    all_passed = true
    for fp in feature_files
        feature = parse_feature(fp)

        # Tag filtering
        if !isempty(tags)
            feature_tag_names = Set(t.name for t in feature.tags)
            if !any(t -> t in feature_tag_names, tags)
                # Check individual scenarios
                # (for v0.1 we skip the whole feature if no feature-level tag matches)
                # A more complete impl would filter per-scenario
            end
        end

        result = run_feature(feature, GLOBAL_REGISTRY)
        all_passed = all_passed && result
    end

    return all_passed
end
