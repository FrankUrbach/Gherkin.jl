# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run all tests
julia --project=. -e 'using Pkg; Pkg.test()'

# Run a single test file
julia --project=. -e 'using Test, Gherkin; include("test/test_parser.jl")'

# Start a REPL with the package loaded
julia --project=. -e 'using Gherkin'
```

## Architecture

The pipeline is: **Parser → AST → Registry lookup → Executor → Reporter**

**Load order matters** (see `src/Gherkin.jl`):
1. `ast.jl` — Immutable structs: `Feature`, `Rule`, `Scenario`, `ScenarioOutline`, `Step`, `DocString`, `DataTable`, `Background`, `Examples`, `Tag`
2. `tagexpr.jl` — Boolean tag expression parser/evaluator (`parse_tag_expr`, `eval_tag_expr`)
3. `expressions.jl` — Cucumber Expression → Regex compiler (`compile_pattern`, `match_step`); supports `{int}`, `{float}`, `{word}`, `{string}`, `{bool}`, `{}`
4. `context.jl` — `ScenarioContext` (Dict-like shared state between steps in a scenario)
5. `registry.jl` — `StepRegistry` with `register!` / `find_step`; raises `UndefinedStep` or `AmbiguousStep`
6. `reporter.jl` — ANSI-colored console output helpers
7. `parser.jl` — Line-by-line `.feature` file parser; entry points `parse_feature(path)` and `parse_feature_string(text)`
8. `executor.jl` — `HookDefinition`, result types, `run_step`, `run_scenario`, `run_feature`, `runspec`; also defines `_report_run_summary` (must follow reporter.jl)
9. `junit.jl` — `write_junit_xml(results, path)`
10. `macros.jl` — `@given/@when/@then/@step/@and/@but`, `@before/@after/@beforeall/@afterall`, `@expect`; all register into module-level globals

**Global state** (in `Gherkin.jl` module):
- `GLOBAL_REGISTRY` — all step definitions
- `BEFORE_HOOKS`, `AFTER_HOOKS`, `BEFORE_ALL_HOOKS`, `AFTER_ALL_HOOKS`
- `reset_registry!()` / `reset_hooks!()` — used in tests to isolate state between test cases

**Key design notes:**
- `Feature.scenarios` is a virtual property (overridden via `Base.getproperty`) that flattens `Rule` blocks; use `feature.children` for the actual stored data
- `ScenarioOutline` expansion happens in the executor (`expand_outline`), not the parser
- `run_scenario` accepts either `Vector{Background}` (feature + rule backgrounds chained) or a single `Union{Background,Nothing}` (backward-compat overload)
- Hooks with non-empty `tags` fields only fire when the scenario's effective tag set (feature ∪ rule ∪ scenario tags) contains at least one matching tag

**Test fixtures** are in `test/fixtures/` as `.feature` files used by the parser and executor tests.
