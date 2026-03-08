# Executor: runs features and scenarios, integrating with Test.jl

# ─── Hook definition ─────────────────────────────────────────────────────────

"""
    HookDefinition

A before/after hook with an optional tag filter.
If `tags` is empty the hook runs for every scenario.
"""
struct HookDefinition
    tags::Vector{String}   # empty = applies to all scenarios
    fn::Function
    location::String
end

# ─── Result types ─────────────────────────────────────────────────────────────

"""Outcome of a single step execution."""
struct StepResult
    step::Step
    status::Symbol          # :pass | :fail | :skip | :undefined
    error_message::String
    duration_ns::Int64
end

"""Outcome of a single scenario (background + steps)."""
struct ScenarioResult
    scenario::Scenario
    status::Symbol          # :pass | :fail | :skip
    step_results::Vector{StepResult}
    duration_ns::Int64
end

"""Outcome of all scenarios in one feature."""
struct FeatureResult
    feature::Feature
    scenario_results::Vector{ScenarioResult}
    duration_ns::Int64
end

"""Outcome of the entire test suite run."""
struct RunResults
    feature_results::Vector{FeatureResult}
    duration_ns::Int64
end

# Convenience predicates
passed(r::ScenarioResult) = r.status == :pass
passed(r::FeatureResult)  = all(passed, r.scenario_results)
passed(r::RunResults)     = all(passed, r.feature_results)

# ─── Tag utilities ─────────────────────────────────────────────────────────────

"""Return the effective tag set for a scenario (its own tags + feature-level tags)."""
function _effective_tags(scenario::Scenario, feature::Feature) :: Set{String}
    tags = Set{String}()
    for t in feature.tags;   push!(tags, t.name); end
    for t in scenario.tags;  push!(tags, t.name); end
    return tags
end

"""
Return true if the scenario passes the include/exclude tag filter.

- `include_tags` empty → all scenarios pass.
- `include_tags` non-empty → scenario must have at least one listed tag.
- `exclude_tags` non-empty → scenario must have none of the listed tags.
"""
function _tag_filter_matches(scenario::Scenario, feature::Feature,
                              include_tags::Vector{String},
                              exclude_tags::Vector{String}) :: Bool
    eff = _effective_tags(scenario, feature)
    !isempty(include_tags) && !any(t -> t in eff, include_tags) && return false
    !isempty(exclude_tags) &&  any(t -> t in eff, exclude_tags) && return false
    return true
end

"""Return true if the hook should run for the given scenario."""
function _hook_applies(hook::HookDefinition, scenario::Scenario, feature::Feature) :: Bool
    isempty(hook.tags) && return true
    eff = _effective_tags(scenario, feature)
    return any(t -> t in eff, hook.tags)
end

# ─── Outline expansion ────────────────────────────────────────────────────────

"""
    expand_outline(outline::ScenarioOutline) :: Vector{Scenario}

Expand a ScenarioOutline into concrete Scenarios by substituting
example row values into step texts, doc strings, and data table cells.
"""
function expand_outline(outline::ScenarioOutline) :: Vector{Scenario}
    scenarios = Scenario[]
    for examples in outline.examples
        header = examples.header
        for (row_idx, row) in enumerate(examples.rows)
            subs = Dict{String,String}(col => val for (col, val) in zip(header, row))
            row_desc = join(["$(h)=$(v)" for (h,v) in zip(header, row)], ", ")
            name = isempty(outline.name) ? "Example $(row_idx): $(row_desc)" :
                                           "$(outline.name) (Example $(row_idx): $(row_desc))"

            new_steps = map(outline.steps) do step
                new_text = _substitute(step.text, subs)
                new_ds   = step.docstring === nothing ? nothing :
                           DocString(step.docstring.content_type,
                                     _substitute(step.docstring.content, subs))
                new_dt   = step.datatable === nothing ? nothing :
                           [[_substitute(c, subs) for c in row_cells]
                            for row_cells in step.datatable]
                Step(step.keyword, new_text, new_ds, new_dt, step.line)
            end

            push!(scenarios,
                  Scenario(name, outline.description, outline.tags, new_steps, outline.line))
        end
    end
    return scenarios
end

function _substitute(text::String, subs::Dict{String,String}) :: String
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

# ─── Step execution ───────────────────────────────────────────────────────────

"""
    run_step(step, context, registry) :: StepResult

Execute a single step and return its result (including timing).
Still calls `Test.@test` to integrate with Test.jl.
"""
function run_step(step::Step, context::ScenarioContext,
                  registry::StepRegistry) :: StepResult
    t0 = time_ns()

    local defn, params
    try
        defn, params = find_step(registry, step.text)
    catch e
        if e isa UndefinedStep
            report_step_undefined(step)
            Test.@test false
            return StepResult(step, :undefined, "Undefined step: $(step.text)",
                              Int64(time_ns() - t0))
        end
        report_step_fail(step, e)
        Test.@test false
        return StepResult(step, :fail, sprint(showerror, e), Int64(time_ns() - t0))
    end

    try
        extra = step.docstring !== nothing ? step.docstring :
                step.datatable !== nothing ? step.datatable : nothing
        if extra !== nothing
            defn.fn(context, params..., extra)
        else
            defn.fn(context, params...)
        end
        report_step_pass(step)
        return StepResult(step, :pass, "", Int64(time_ns() - t0))
    catch e
        errmsg = sprint(showerror, e)
        report_step_fail(step, e)
        Test.@test false
        return StepResult(step, :fail, errmsg, Int64(time_ns() - t0))
    end
end

# ─── Scenario execution ───────────────────────────────────────────────────────

"""
    run_scenario(scenario, background, registry; feature) :: ScenarioResult

Execute a single scenario (background steps first) and return the result.
`feature` is used for tag-based hook filtering; defaults to a no-tag dummy.
"""
function run_scenario(scenario::Scenario,
                      background::Union{Background,Nothing},
                      registry::StepRegistry;
                      feature::Union{Feature,Nothing} = nothing) :: ScenarioResult
    t0 = time_ns()
    context = ScenarioContext()

    _feat = feature === nothing ?
            Feature("", "", "", Tag[], nothing, AbstractScenario[], 0) : feature

    # Run applicable @before hooks
    for hook in BEFORE_HOOKS
        _hook_applies(hook, scenario, _feat) || continue
        try
            hook.fn(context)
        catch e
            @warn "Before hook failed" exception=e
        end
    end

    step_results = StepResult[]
    failed = false

    # Background steps
    if background !== nothing
        for step in background.steps
            if failed
                push!(step_results, StepResult(step, :skip, "", 0))
                report_step_skipped(step)
                continue
            end
            sr = run_step(step, context, registry)
            push!(step_results, sr)
            sr.status != :pass && (failed = true)
        end
    end

    # Scenario steps
    for step in scenario.steps
        if failed
            push!(step_results, StepResult(step, :skip, "", 0))
            report_step_skipped(step)
            continue
        end
        sr = run_step(step, context, registry)
        push!(step_results, sr)
        sr.status != :pass && (failed = true)
    end

    # Run applicable @after hooks
    for hook in AFTER_HOOKS
        _hook_applies(hook, scenario, _feat) || continue
        try
            hook.fn(context)
        catch e
            @warn "After hook failed" exception=e
        end
    end

    status = failed ? :fail : :pass
    return ScenarioResult(scenario, status, step_results, Int64(time_ns() - t0))
end

# ─── Feature execution ────────────────────────────────────────────────────────

"""
    run_feature(feature, registry; include_tags, exclude_tags) :: FeatureResult

Run all (non-filtered) scenarios in a feature, wrapped in a Test.jl testset.
"""
function run_feature(feature::Feature, registry::StepRegistry;
                     include_tags::Vector{String} = String[],
                     exclude_tags::Vector{String} = String[]) :: FeatureResult
    t0 = time_ns()
    report_feature_start(feature)
    all_scenarios = expand_scenarios(feature)
    scenario_results = ScenarioResult[]

    Test.@testset "$(feature.name)" begin
        for scenario in all_scenarios
            report_scenario_start(scenario)

            # Tag filtering — skipped scenarios don't get a testset
            if !_tag_filter_matches(scenario, feature, include_tags, exclude_tags)
                sr = ScenarioResult(scenario, :skip, StepResult[], 0)
                push!(scenario_results, sr)
                report_scenario_skipped(scenario)
                continue
            end

            sr_ref = Ref{ScenarioResult}()
            Test.@testset "$(scenario.name)" begin
                result = run_scenario(scenario, feature.background, registry;
                                      feature=feature)
                sr_ref[] = result
            end
            push!(scenario_results, sr_ref[])
            report_scenario_result(scenario, sr_ref[].status == :pass)
        end
    end

    total        = length(all_scenarios)
    passed_count = count(r -> r.status == :pass, scenario_results)
    report_feature_result(feature, passed_count, total)

    return FeatureResult(feature, scenario_results, Int64(time_ns() - t0))
end

# ─── Full suite runner ────────────────────────────────────────────────────────

"""
    runspec(; features_dir, steps_dir, include_tags, exclude_tags, junit_output) :: RunResults

Discover and run all feature files.

# Keyword arguments
- `features_dir` – directory to search for `.feature` files (default: `"features"`)
- `steps_dir`    – directory to `include()` step-definition `.jl` files from;
                   pass `nothing` to skip auto-loading (default: `"features/steps"`)
- `include_tags` – run only scenarios that have at least one of these tags
- `exclude_tags` – skip scenarios that have any of these tags
- `junit_output` – write a JUnit XML report to this path (default: `nothing`)
"""
function runspec(;
    features_dir::String             = "features",
    steps_dir::Union{String,Nothing} = joinpath("features", "steps"),
    include_tags::Vector{String}     = String[],
    exclude_tags::Vector{String}     = String[],
    junit_output::Union{String,Nothing} = nothing
) :: RunResults

    t0 = time_ns()

    # Auto-load step definition files
    if steps_dir !== nothing && isdir(steps_dir)
        for (root, _, files) in walkdir(steps_dir)
            for file in sort(files)
                endswith(file, ".jl") && include(joinpath(root, file))
            end
        end
    end

    # Collect feature files
    feature_files = String[]
    if isdir(features_dir)
        for (root, _, files) in walkdir(features_dir)
            for file in files
                endswith(file, ".feature") && push!(feature_files, joinpath(root, file))
            end
        end
    end
    sort!(feature_files)

    # BeforeAll hooks
    for fn in BEFORE_ALL_HOOKS
        try fn() catch e; @warn "BeforeAll hook failed" exception=e; end
    end

    feature_results = FeatureResult[]
    for fp in feature_files
        feature = parse_feature(fp)
        result  = run_feature(feature, GLOBAL_REGISTRY;
                              include_tags=include_tags, exclude_tags=exclude_tags)
        push!(feature_results, result)
    end

    # AfterAll hooks
    for fn in AFTER_ALL_HOOKS
        try fn() catch e; @warn "AfterAll hook failed" exception=e; end
    end

    results = RunResults(feature_results, Int64(time_ns() - t0))

    junit_output !== nothing && write_junit_xml(results, junit_output)
    _report_run_summary(results)

    return results
end

# ─── Suite summary reporter ───────────────────────────────────────────────────
# Defined here (after RunResults) rather than reporter.jl to avoid load-order issues.

"""
    report_run_summary(results::RunResults)

Print a summary table for the entire test suite run.
"""
function report_run_summary(results::RunResults)
    _report_run_summary(results)
end

function _report_run_summary(results::RunResults)
    total   = sum(length(fr.scenario_results) for fr in results.feature_results; init=0)
    n_pass  = sum(count(r -> r.status == :pass, fr.scenario_results)
                  for fr in results.feature_results; init=0)
    n_fail  = sum(count(r -> r.status == :fail, fr.scenario_results)
                  for fr in results.feature_results; init=0)
    n_skip  = sum(count(r -> r.status == :skip, fr.scenario_results)
                  for fr in results.feature_results; init=0)
    time_s  = round(results.duration_ns / 1e9, digits=2)
    nfeat   = length(results.feature_results)

    color = n_fail > 0 ? ANSI_RED : ANSI_GREEN
    println()
    println("$(ANSI_BOLD)$(color)═══ Gherkin Test Suite ═══$(ANSI_RESET)")
    println("  Features:  $(nfeat)")
    print("  Scenarios: $(total)  (")
    print("$(ANSI_GREEN)$(n_pass) passed$(ANSI_RESET)")
    n_fail > 0 && print("  $(ANSI_RED)$(n_fail) failed$(ANSI_RESET)")
    n_skip > 0 && print("  $(ANSI_YELLOW)$(n_skip) skipped$(ANSI_RESET)")
    println(")")
    println("  Time:      $(time_s)s")
end
