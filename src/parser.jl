# Line-by-line Gherkin parser

# Keyword detection helpers
function _strip_keyword(line::AbstractString, kw::AbstractString)
    stripped = lstrip(line)
    if startswith(stripped, kw)
        rest = stripped[nextind(stripped, length(kw)):end]
        return String(strip(rest))
    end
    return nothing
end

function _detect_step_keyword(line::AbstractString) :: Union{Tuple{StepKeyword, String}, Nothing}
    stripped = lstrip(line)
    for (kw_str, kw_enum) in (
        ("Given ", GivenKeyword),
        ("When ",  WhenKeyword),
        ("Then ",  ThenKeyword),
        ("And ",   AndKeyword),
        ("But ",   ButKeyword),
    )
        if startswith(stripped, kw_str)
            text = String(strip(stripped[nextind(stripped, length(kw_str)-1):end]))
            return (kw_enum, text)
        end
    end
    return nothing
end

function _parse_tags(line::AbstractString) :: Vector{Tag}
    tags = Tag[]
    for token in split(strip(line))
        if startswith(token, "@")
            push!(tags, Tag(String(token[nextind(token, 1):end])))
        end
    end
    return tags
end

function _parse_table_row(line::AbstractString) :: Vector{String}
    stripped = strip(line)
    # Remove leading and trailing |
    if startswith(stripped, "|")
        stripped = stripped[nextind(stripped, 1):end]
    end
    if endswith(stripped, "|")
        stripped = stripped[1:prevind(stripped, lastindex(stripped))]
    end
    return [String(strip(cell)) for cell in split(stripped, "|")]
end

# DocString delimiter detection
function _is_docstring_delimiter(line::AbstractString) :: Bool
    s = lstrip(line)
    return startswith(s, "\"\"\"") || startswith(s, "```")
end

function _docstring_delimiter_type(line::AbstractString) :: String
    s = lstrip(line)
    startswith(s, "\"\"\"") && return "\"\"\""
    startswith(s, "```")   && return "```"
    return ""
end

# Compute leading whitespace count for docstring indentation stripping
function _leading_spaces(line::AbstractString) :: Int
    count = 0
    for c in line
        if c == ' '
            count += 1
        elseif c == '\t'
            count += 4
        else
            break
        end
    end
    return count
end

function _strip_indent(line::AbstractString, n::Int) :: String
    removed = 0
    i = firstindex(line)
    while i <= lastindex(line) && removed < n
        c = line[i]
        if c == ' '
            removed += 1
            i = nextind(line, i)
        elseif c == '\t'
            removed += 4
            i = nextind(line, i)
        else
            break
        end
    end
    return line[i:end]
end

"""
    parse_feature(filepath::String) :: Feature

Parse a Gherkin .feature file and return a Feature AST node.
"""
function parse_feature(filepath::String) :: Feature
    lines = readlines(filepath)
    return _parse_lines(lines, filepath)
end

"""
    parse_feature_string(content::String; uri::String="<string>") :: Feature

Parse Gherkin content from a string (useful for testing).
"""
function parse_feature_string(content::String; uri::String="<string>") :: Feature
    lines = split(content, '\n')
    return _parse_lines(lines, uri)
end

mutable struct _ParseState
    feature_name::String
    feature_description::Vector{String}
    feature_tags::Vector{Tag}
    feature_line::Int
    background::Union{Background, Nothing}
    scenarios::Vector{AbstractScenario}

    # Current element being built
    pending_tags::Vector{Tag}

    # Current scenario/background being built
    current_kind::Symbol   # :none, :background, :scenario, :outline
    current_name::String
    current_description::Vector{String}
    current_steps::Vector{Step}
    current_tags::Vector{Tag}
    current_line::Int
    current_examples::Vector{Examples}

    # Current examples block
    in_examples::Bool
    examples_name::String
    examples_tags::Vector{Tag}
    examples_header::Vector{String}
    examples_rows::Vector{Vector{String}}
    examples_line::Int

    # DocString state
    in_docstring::Bool
    docstring_delimiter::String
    docstring_content_type::String
    docstring_lines::Vector{String}
    docstring_indent::Int
    current_step_for_docstring::Union{Step, Nothing}

    # DataTable state
    in_datatable::Bool
    datatable_rows::Vector{Vector{String}}
    current_step_for_datatable::Union{Step, Nothing}
end

function _new_parse_state()
    _ParseState(
        "", String[], Tag[], 0,  # feature
        nothing,                  # background
        AbstractScenario[],       # scenarios
        Tag[],                    # pending_tags
        :none, "", String[], Step[], Tag[], 0, Examples[],  # current element
        false, "", Tag[], String[], Vector{String}[], 0,    # examples
        false, "", "", String[], 0, nothing,                # docstring
        false, Vector{String}[], nothing,                   # datatable
    )
end

function _flush_step!(state::_ParseState, steps::Vector{Step})
    # Finalize any step that was accumulating a docstring or datatable
    # (called when we detect a new step or end of scenario)
    # Steps are added to `steps` directly as they're parsed, with docstring/datatable=nothing
    # We patch the last step when the docstring/datatable ends
    nothing
end

function _finish_current_scenario!(state::_ParseState)
    if state.current_kind == :none
        return
    end

    # Close any open datatable
    if state.in_datatable && !isempty(state.current_steps)
        steps = state.current_steps
        last_step = steps[end]
        steps[end] = Step(last_step.keyword, last_step.text, last_step.docstring,
                          deepcopy(state.datatable_rows), last_step.line)
        state.in_datatable = false
        empty!(state.datatable_rows)
    end

    if state.current_kind == :background
        state.background = Background(
            join(state.current_description, "\n"),
            copy(state.current_steps),
            state.current_line
        )
    elseif state.current_kind == :scenario
        sc = Scenario(
            state.current_name,
            join(state.current_description, "\n"),
            copy(state.current_tags),
            copy(state.current_steps),
            state.current_line
        )
        push!(state.scenarios, sc)
    elseif state.current_kind == :outline
        # Close current examples block if open
        _finish_current_examples!(state)
        outline = ScenarioOutline(
            state.current_name,
            join(state.current_description, "\n"),
            copy(state.current_tags),
            copy(state.current_steps),
            copy(state.current_examples),
            state.current_line
        )
        push!(state.scenarios, outline)
    end

    # Reset
    state.current_kind = :none
    state.current_name = ""
    empty!(state.current_description)
    empty!(state.current_steps)
    empty!(state.current_tags)
    state.current_line = 0
    empty!(state.current_examples)
    state.in_examples = false
    empty!(state.examples_header)
    empty!(state.examples_rows)
end

function _finish_current_examples!(state::_ParseState)
    if state.in_examples && !isempty(state.examples_header)
        ex = Examples(
            state.examples_name,
            copy(state.examples_tags),
            copy(state.examples_header),
            deepcopy(state.examples_rows),
            state.examples_line
        )
        push!(state.current_examples, ex)
        state.in_examples = false
        state.examples_name = ""
        empty!(state.examples_tags)
        empty!(state.examples_header)
        empty!(state.examples_rows)
    end
end

function _parse_lines(lines, filepath::String) :: Feature
    state = _new_parse_state()
    in_feature = false

    for (lineno, raw_line) in enumerate(lines)
        line = string(raw_line)  # ensure String

        # Handle docstring mode
        if state.in_docstring
            s = lstrip(line)
            delim = state.docstring_delimiter
            if startswith(s, delim)
                # End of docstring — patch the last step
                content = join(state.docstring_lines, "\n")
                ds = DocString(state.docstring_content_type, content)
                steps = state.in_examples ? state.current_steps :
                        state.current_kind == :background ? state.current_steps :
                        state.current_steps
                if !isempty(steps)
                    last_step = steps[end]
                    steps[end] = Step(last_step.keyword, last_step.text, ds, last_step.datatable, last_step.line)
                end
                state.in_docstring = false
                state.docstring_delimiter = ""
                state.docstring_content_type = ""
                empty!(state.docstring_lines)
                state.docstring_indent = 0
            else
                push!(state.docstring_lines, _strip_indent(line, state.docstring_indent))
            end
            continue
        end

        trimmed = strip(line)

        # Skip empty lines and comments
        if isempty(trimmed) || startswith(trimmed, "#")
            continue
        end

        # Tag lines
        if startswith(trimmed, "@")
            tags = _parse_tags(trimmed)
            # Tags always go into pending_tags; when Feature/Scenario is found
            # they are consumed from there
            append!(state.pending_tags, tags)
            continue
        end

        # Feature keyword
        if (name = _strip_keyword(line, "Feature:")) !== nothing
            in_feature = true
            state.feature_name = name
            state.feature_line = lineno
            state.feature_tags = copy(state.pending_tags)
            empty!(state.pending_tags)
            continue
        end

        if !in_feature
            continue
        end

        # Background keyword
        if (name = _strip_keyword(line, "Background:")) !== nothing
            _finish_current_scenario!(state)
            state.current_kind = :background
            state.current_name = name
            state.current_line = lineno
            empty!(state.current_description)
            empty!(state.current_steps)
            continue
        end

        # Scenario Outline keyword (must check before Scenario)
        if (name = _strip_keyword(line, "Scenario Outline:")) !== nothing ||
           (name = _strip_keyword(line, "Scenario Template:")) !== nothing
            _finish_current_scenario!(state)
            state.current_kind = :outline
            state.current_name = name
            state.current_line = lineno
            state.current_tags = copy(state.pending_tags)
            empty!(state.pending_tags)
            empty!(state.current_description)
            empty!(state.current_steps)
            empty!(state.current_examples)
            continue
        end

        # Scenario keyword
        if (name = _strip_keyword(line, "Scenario:")) !== nothing
            _finish_current_scenario!(state)
            state.current_kind = :scenario
            state.current_name = name
            state.current_line = lineno
            state.current_tags = copy(state.pending_tags)
            empty!(state.pending_tags)
            empty!(state.current_description)
            empty!(state.current_steps)
            continue
        end

        # Examples keyword (inside Scenario Outline)
        if state.current_kind == :outline &&
           ((name = _strip_keyword(line, "Examples:")) !== nothing ||
            (name = _strip_keyword(line, "Scenarios:")) !== nothing)
            _finish_current_examples!(state)
            state.in_examples = true
            state.examples_name = name
            state.examples_tags = copy(state.pending_tags)
            empty!(state.pending_tags)
            state.examples_line = lineno
            empty!(state.examples_header)
            empty!(state.examples_rows)
            # Close any open datatable in steps
            if state.in_datatable && !isempty(state.current_steps)
                last_step = state.current_steps[end]
                state.current_steps[end] = Step(last_step.keyword, last_step.text,
                    last_step.docstring, deepcopy(state.datatable_rows), last_step.line)
                state.in_datatable = false
                empty!(state.datatable_rows)
            end
            continue
        end

        # Data table row
        if startswith(lstrip(line), "|")
            row = _parse_table_row(trimmed)
            if state.in_examples
                if isempty(state.examples_header)
                    state.examples_header = row
                else
                    push!(state.examples_rows, row)
                end
            else
                # Data table for last step
                if !state.in_datatable
                    state.in_datatable = true
                    empty!(state.datatable_rows)
                end
                push!(state.datatable_rows, row)
            end
            continue
        else
            # Not a table row — close datatable if open
            if state.in_datatable && !isempty(state.current_steps)
                last_step = state.current_steps[end]
                state.current_steps[end] = Step(last_step.keyword, last_step.text,
                    last_step.docstring, deepcopy(state.datatable_rows), last_step.line)
                state.in_datatable = false
                empty!(state.datatable_rows)
            end
        end

        # DocString start
        if _is_docstring_delimiter(line)
            delim = _docstring_delimiter_type(line)
            state.in_docstring = true
            state.docstring_delimiter = delim
            state.docstring_indent = _leading_spaces(line)
            # Content type: text after the delimiter on the same line
            s = lstrip(line)
            after_delim = strip(s[nextind(s, length(delim)):end])
            state.docstring_content_type = after_delim
            empty!(state.docstring_lines)
            continue
        end

        # Step keywords
        if (step_info = _detect_step_keyword(line)) !== nothing
            kw, text = step_info
            step = Step(kw, text, nothing, nothing, lineno)
            push!(state.current_steps, step)
            continue
        end

        # Free-text description lines (after Feature/Scenario/Background header but before first step)
        if state.current_kind == :none && in_feature
            push!(state.feature_description, trimmed)
        elseif state.current_kind != :none && isempty(state.current_steps) && !state.in_examples
            push!(state.current_description, trimmed)
        end
    end

    # Finalize any open datatable
    if state.in_datatable && !isempty(state.current_steps)
        last_step = state.current_steps[end]
        state.current_steps[end] = Step(last_step.keyword, last_step.text,
            last_step.docstring, deepcopy(state.datatable_rows), last_step.line)
        state.in_datatable = false
    end

    _finish_current_scenario!(state)

    return Feature(
        filepath,
        state.feature_name,
        join(state.feature_description, "\n"),
        state.feature_tags,
        state.background,
        state.scenarios,
        state.feature_line
    )
end
