# Gherkin.jl

A complete Gherkin/BDD test runner for Julia, similar to Cucumber.

[![Julia](https://img.shields.io/badge/Julia-1.9+-blue.svg)](https://julialang.org)
[![CI](https://github.com/FrankUrbach/Gherkin.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/FrankUrbach/Gherkin.jl/actions/workflows/ci.yml)

## Features

- Full Gherkin parser: Feature, Background, Scenario, Scenario Outline, Given/When/Then/And/But, Doc Strings, Data Tables, Tags, Comments
- Step definition registry with both Cucumber Expression string patterns (`"connection opens with {word}"`) and Regex (`r"connection opens with (\w+)"`)
- `@given`, `@when`, `@then`, `@step`, `@and`, `@but` macros — all equivalent
- `ScenarioContext` for sharing state between steps
- Runner integrated with Julia's `Test.jl` (Feature → `@testset`, Scenario → nested `@testset`)
- Before/after hooks via `@before` / `@after`
- Console reporter with colored output
- `runspec()` for discovering feature files and step definition files

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/FrankUrbach/Gherkin.jl")
```

## Quick Start

### 1. Write a feature file (`features/calculator.feature`)

```gherkin
Feature: Basic calculator

  Background:
    Given a new calculator

  Scenario: Adding two numbers
    When I add 3 and 4
    Then the result is 7

  Scenario Outline: Adding <a> and <b>
    When I add <a> and <b>
    Then the result is <result>

    Examples:
      | a | b | result |
      | 1 | 2 | 3      |
      | 5 | 5 | 10     |
```

### 2. Write step definitions (`features/steps/calculator_steps.jl`)

```julia
using Gherkin

@given("a new calculator") do context
    context[:result] = 0
end

@when("I add {int} and {int}") do context, a, b
    context[:result] = a + b
end

@then("the result is {int}") do context, expected
    @expect context[:result] == expected
end
```

### 3. Run with `runspec()`

```julia
using Gherkin
runspec(features_dir="features", steps_dir="features/steps")
```

Or integrate with `Test.jl` in your `test/runtests.jl`.

## Cucumber Expressions

The following parameter types are supported:

| Type | Pattern | Julia Type |
|------|---------|------------|
| `{int}` | `-?[0-9]+` | `Int` |
| `{float}` | `-?[0-9]*\.[0-9]+` | `Float64` |
| `{word}` | `[^\s]+` | `String` |
| `{string}` | `"..."` or `'...'` | `String` (without quotes) |
| `{bool}` | `true\|false` | `Bool` |
| `{}` | `.+` | `String` |
| `{name}` | `.+` | `String` |

Regex patterns can also be used directly:

```julia
@given(r"connection (\w+) database: (\w+)") do context, action, dbname
    # action and dbname are strings
end
```

## ScenarioContext

Steps share state through a `ScenarioContext`:

```julia
@given("a value of {int}") do context, n
    context[:value] = n
end

@then("the value is {int}") do context, expected
    @expect context[:value] == expected
end
```

## Doc Strings

Steps can receive a doc string as an extra argument:

```gherkin
Given a query
  """typeql
  match $x isa person;
  """
```

```julia
@given("a query") do context, docstring::DocString
    # docstring.content_type == "typeql"
    # docstring.content == "match \$x isa person;"
end
```

## Data Tables

Steps can receive a data table:

```gherkin
Given the following users:
  | name  | age |
  | Alice | 30  |
  | Bob   | 25  |
```

```julia
@given("the following users:") do context, table::DataTable
    # table is a Vector{Vector{String}}
    # table[1] == ["name", "age"]  (header)
    # table[2] == ["Alice", "30"]
end
```

## Hooks

```julia
@before do context
    # runs before each scenario
    context[:db] = connect_to_test_db()
end

@after do context
    # runs after each scenario
    close(context[:db])
end
```

## License

MIT
