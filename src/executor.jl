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

"""
Return the effective tag set for a scenario:
  feature tags ∪ rule tags (if inside a Rule) ∪ scenario's own tags.
"""
function _effective_tags(scenario::Scenario, feature::Feature;
                          rule::Union{Rule,Nothing} = nothing) :: Set{String}
    tags = Set{String}()
    for t in feature.tags;  push!(tags, t.name); end
    if rule !== nothing
        for t in rule.tags; push!(tags, t.name); end
    end
    for t in scenario.tags; push!(tags, t.name); end
    return tags
end

"""
Build a tag-filter closure from the supplied parameters.

Priority (highest first):
1. `tags` — a boolean expression string (e.g. `"@smoke and not @wip"`);
   parsed via `parse_tag_expr` / `eval_tag_expr`.
2. `include_tags` / `exclude_tags` — simple allow/block lists (legacy).
3. If all are empty/blank — every scenario passes (`TagAll` semantics).

Returns `(eff::Set{String}) -> Bool`.
"""
function _build_tag_filter(include_tags::Vector{String},
                            exclude_tags::Vector{String},
                            tags::String) :: Function
    if !isempty(strip(tags))
        expr = parse_tag_expr(tags)
        return (eff::Set{String}) -> eval_tag_expr(expr, eff)
    elseif !isempty(include_tags) || !isempty(exclude_tags)
        return function (eff::Set{String})
            !isempty(include_tags) && !any(t -> t in eff, include_tags) && return false
            !isempty(exclude_tags) &&  any(t -> t in eff, exclude_tags) && return false
            return true
        end
    else
        return (_::Set{String}) -> true
    end
end

"""Return true if the hook should run for the given scenario."""
function _hook_applies(hook::HookDefinition, scenario::Scenario, feature::Feature;
                       rule::Union{Rule,Nothing} = nothing) :: Bool
    isempty(hook.tags) && return true
    eff = _effective_tags(scenario, feature; rule=rule)
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
Flattens Rule blocks.
"""
function expand_scenarios(feature::Feature) :: Vector{Scenario}
    result = Scenario[]
    for child in feature.children
        if child isa Scenario
            push!(result, child)
        elseif child isa ScenarioOutline
            append!(result, expand_outline(child))
        elseif child isa Rule
            for sc in child.scenarios
                if sc isa Scenario
                    push!(result, sc)
                elseif sc isa ScenarioOutline
                    append!(result, expand_outline(sc))
                end
            end
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
    run_scenario(scenario, backgrounds, registry; feature, rule) :: ScenarioResult

Execute a single scenario with zero or more background steps (chained) and
return the result.  `backgrounds` is a `Vector{Background}` so that a
feature-level background and a rule-level background can both be run in order.
`feature` and `rule` are used for tag-based hook filtering.
"""
function run_scenario(scenario::Scenario,
                      backgrounds::Vector{Background},
                      registry::StepRegistry;
                      feature::Union{Feature,Nothing} = nothing,
                      rule::Union{Rule,Nothing}   = nothing) :: ScenarioResult
    t0 = time_ns()
    context = ScenarioContext()

    _feat = feature === nothing ?
            Feature("", "", "", Tag[], nothing, FeatureChild[], 0) : feature

    # Run applicable @before hooks
    for hook in BEFORE_HOOKS
        _hook_applies(hook, scenario, _feat; rule=rule) || continue
        try
            hook.fn(context)
        catch e
            @warn "Before hook failed" exception=e
        end
    end

    step_results = StepResult[]
    failed = false

    # Background steps (feature-level first, then rule-level)
    for bg in backgrounds
        for step in bg.steps
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
        _hook_applies(hook, scenario, _feat; rule=rule) || continue
        try
            hook.fn(context)
        catch e
            @warn "After hook failed" exception=e
        end
    end

    status = failed ? :fail : :pass
    return ScenarioResult(scenario, status, step_results, Int64(time_ns() - t0))
end

# Backward-compatible single-background overload
function run_scenario(scenario::Scenario,
                      background::Union{Background,Nothing},
                      registry::StepRegistry;
                      feature::Union{Feature,Nothing} = nothing,
                      rule::Union{Rule,Nothing}       = nothing) :: ScenarioResult
    bgs = background === nothing ? Background[] : [background]
    return run_scenario(scenario, bgs, registry; feature=feature, rule=rule)
end

# ─── Internal helpers for feature/rule execution ──────────────────────────────

"""Run all concrete scenarios that come from `sc` (expanding outlines as needed)."""
function _run_abstract_scenario!(scenario_results::Vector{ScenarioResult},
                                  sc::AbstractScenario,
                                  backgrounds::Vector{Background},
                                  feature::Feature,
                                  rule::Union{Rule,Nothing},
                                  registry::StepRegistry,
                                  tag_filter::Function)
    concrete = sc isa ScenarioOutline ? expand_outline(sc) : [sc]
    for scenario in concrete
        eff = _effective_tags(scenario, feature; rule=rule)
        if !tag_filter(eff)
            sr = ScenarioResult(scenario, :skip, StepResult[], 0)
            push!(scenario_results, sr)
            report_scenario_skipped(scenario)
            continue
        end

        report_scenario_start(scenario)
        sr_ref = Ref{ScenarioResult}()
        Test.@testset "$(scenario.name)" begin
            result = run_scenario(scenario, backgrounds, registry;
                                  feature=feature, rule=rule)
            sr_ref[] = result
        end
        push!(scenario_results, sr_ref[])
        report_scenario_result(scenario, sr_ref[].status == :pass)
    end
end

"""Run all scenarios inside a Rule block (with merged backgrounds)."""
function _run_rule!(scenario_results::Vector{ScenarioResult},
                    rule::Rule,
                    feature::Feature,
                    registry::StepRegistry,
                    tag_filter::Function)
    # Merge feature-level background + rule-level background
    backgrounds = Background[]
    feature.background !== nothing && push!(backgrounds, feature.background)
    rule.background   !== nothing && push!(backgrounds, rule.background)

    Test.@testset "Rule: $(rule.name)" begin
        for sc in rule.scenarios
            _run_abstract_scenario!(scenario_results, sc, backgrounds,
                                    feature, rule, registry, tag_filter)
        end
    end
end

# ─── Feature execution ────────────────────────────────────────────────────────

"""
    run_feature(feature, registry; include_tags, exclude_tags, tags) :: FeatureResult

Run all (non-filtered) scenarios in a feature, wrapped in a Test.jl testset.
Rule blocks are executed with nested testsets and their own (merged) background.

# Tag filtering (pick one style)
- `tags`         – boolean expression string: `"@smoke and not @wip"`
- `include_tags` – simple allow-list (any match → include)
- `exclude_tags` – simple block-list (any match → skip)
"""
function run_feature(feature::Feature, registry::StepRegistry;
                     include_tags::Vector{String} = String[],
                     exclude_tags::Vector{String} = String[],
                     tags::String = "") :: FeatureResult
    t0 = time_ns()
    tag_filter = _build_tag_filter(include_tags, exclude_tags, tags)
    report_feature_start(feature)
    scenario_results = ScenarioResult[]

    # Feature-level background (used for top-level scenarios; Rule execution merges its own)
    feat_backgrounds = feature.background !== nothing ? [feature.background] : Background[]

    Test.@testset "$(feature.name)" begin
        for child in feature.children
            if child isa Rule
                _run_rule!(scenario_results, child, feature, registry, tag_filter)
            elseif child isa AbstractScenario
                _run_abstract_scenario!(scenario_results, child, feat_backgrounds,
                                        feature, nothing, registry, tag_filter)
            end
        end
    end

    total        = length(scenario_results)
    passed_count = count(r -> r.status == :pass, scenario_results)
    report_feature_result(feature, passed_count, total)

    return FeatureResult(feature, scenario_results, Int64(time_ns() - t0))
end

# ─── Full suite runner ────────────────────────────────────────────────────────

"""
    runspec(; features_dir, steps_dir, include_tags, exclude_tags, tags, junit_output) :: RunResults

Discover and run all feature files.

# Keyword arguments
- `features_dir` – directory to search for `.feature` files (default: `"features"`)
- `steps_dir`    – directory to `include()` step-definition `.jl` files from;
                   pass `nothing` to skip auto-loading (default: `"features/steps"`)
- `tags`         – boolean tag expression string (e.g. `"@smoke and not @wip"`)
- `include_tags` – run only scenarios that have at least one of these tags (legacy)
- `exclude_tags` – skip scenarios that have any of these tags (legacy)
- `junit_output` – write a JUnit XML report to this path (default: `nothing`)
"""
function runspec(;
    features_dir::String             = "features",
    steps_dir::Union{String,Nothing} = joinpath("features", "steps"),
    include_tags::Vector{String}     = String[],
    exclude_tags::Vector{String}     = String[],
    tags::String                     = "",
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
                              include_tags=include_tags, exclude_tags=exclude_tags, tags=tags)
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
