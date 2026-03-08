# Line-by-line Gherkin parser (Gherkin 6 conformant)

# ─── Keyword detection helpers ────────────────────────────────────────────────

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
        ("* ",     StarKeyword),
    )
        if startswith(stripped, kw_str)
            text = String(strip(stripped[nextind(stripped, length(kw_str)-1):end]))
            return (kw_enum, text)
        end
    end
    # Handle bare `*` with no text (edge case)
    if startswith(stripped, "*") && (length(stripped) == 1 || isspace(stripped[2]))
        rest = length(stripped) > 1 ? String(strip(stripped[3:end])) : ""
        return (StarKeyword, rest)
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
    if startswith(stripped, "|")
        stripped = stripped[nextind(stripped, 1):end]
    end
    if endswith(stripped, "|")
        stripped = stripped[1:prevind(stripped, lastindex(stripped))]
    end
    return [String(strip(cell)) for cell in split(stripped, "|")]
end

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

function _leading_spaces(line::AbstractString) :: Int
    count = 0
    for c in line
        c == ' '  && (count += 1; continue)
        c == '\t' && (count += 4; continue)
        break
    end
    return count
end

function _strip_indent(line::AbstractString, n::Int) :: String
    removed = 0
    i = firstindex(line)
    while i <= lastindex(line) && removed < n
        c = line[i]
        if c == ' ';  removed += 1; i = nextind(line, i)
        elseif c == '\t'; removed += 4; i = nextind(line, i)
        else break
        end
    end
    return line[i:end]
end

# ─── Parse state ──────────────────────────────────────────────────────────────

mutable struct _ParseState
    # Feature-level
    feature_name::String
    feature_description::Vector{String}
    feature_tags::Vector{Tag}
    feature_line::Int
    background::Union{Background, Nothing}   # feature-level background
    children::Vector{FeatureChild}           # top-level children (scenarios + rules)

    # Tags accumulated before the next keyword
    pending_tags::Vector{Tag}

    # Current scenario / background being built
    current_kind::Symbol   # :none | :background | :scenario | :outline
    current_name::String
    current_description::Vector{String}
    current_steps::Vector{Step}
    current_tags::Vector{Tag}
    current_line::Int
    current_examples::Vector{Examples}

    # Examples block
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

    # DataTable state
    in_datatable::Bool
    datatable_rows::Vector{Vector{String}}

    # Rule state (Gherkin 6)
    in_rule::Bool
    rule_name::String
    rule_description::Vector{String}
    rule_tags::Vector{Tag}
    rule_background::Union{Background, Nothing}
    rule_scenarios::Vector{AbstractScenario}
    rule_line::Int
end

function _new_parse_state()
    _ParseState(
        "", String[], Tag[], 0,         # feature header
        nothing,                         # feature background
        FeatureChild[],                  # children
        Tag[],                           # pending_tags
        :none, "", String[], Step[], Tag[], 0, Examples[],   # current element
        false, "", Tag[], String[], Vector{String}[], 0,     # examples
        false, "", "", String[], 0,      # docstring
        false, Vector{String}[],         # datatable
        false, "", String[], Tag[], nothing, AbstractScenario[], 0,  # rule
    )
end

# ─── Finish helpers ───────────────────────────────────────────────────────────

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
        state.in_examples      = false
        state.examples_name    = ""
        empty!(state.examples_tags)
        empty!(state.examples_header)
        empty!(state.examples_rows)
    end
end

function _close_open_datatable!(state::_ParseState)
    if state.in_datatable && !isempty(state.current_steps)
        last_step = state.current_steps[end]
        state.current_steps[end] = Step(
            last_step.keyword, last_step.text,
            last_step.docstring, deepcopy(state.datatable_rows),
            last_step.line)
        state.in_datatable = false
        empty!(state.datatable_rows)
    end
end

"""Push the finished scenario/outline into the right bucket (rule or top-level)."""
function _push_scenario!(state::_ParseState, sc::AbstractScenario)
    if state.in_rule
        push!(state.rule_scenarios, sc)
    else
        push!(state.children, sc)
    end
end

function _finish_current_scenario!(state::_ParseState)
    state.current_kind == :none && return

    _close_open_datatable!(state)

    if state.current_kind == :background
        bg = Background(
            join(state.current_description, "\n"),
            copy(state.current_steps),
            state.current_line
        )
        if state.in_rule
            state.rule_background = bg
        else
            state.background = bg
        end

    elseif state.current_kind == :scenario
        sc = Scenario(
            state.current_name,
            join(state.current_description, "\n"),
            copy(state.current_tags),
            copy(state.current_steps),
            state.current_line
        )
        _push_scenario!(state, sc)

    elseif state.current_kind == :outline
        _finish_current_examples!(state)
        outline = ScenarioOutline(
            state.current_name,
            join(state.current_description, "\n"),
            copy(state.current_tags),
            copy(state.current_steps),
            copy(state.current_examples),
            state.current_line
        )
        _push_scenario!(state, outline)
    end

    # Reset current element
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

function _finish_current_rule!(state::_ParseState)
    state.in_rule || return
    _finish_current_scenario!(state)
    rule = Rule(
        state.rule_name,
        join(state.rule_description, "\n"),
        copy(state.rule_tags),
        state.rule_background,
        copy(state.rule_scenarios),
        state.rule_line
    )
    push!(state.children, rule)
    state.in_rule          = false
    state.rule_name        = ""
    empty!(state.rule_description)
    empty!(state.rule_tags)
    state.rule_background  = nothing
    empty!(state.rule_scenarios)
    state.rule_line        = 0
end

# ─── Public entry points ──────────────────────────────────────────────────────

"""
    parse_feature(filepath::String) :: Feature

Parse a Gherkin `.feature` file and return the `Feature` AST node.
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

# ─── Main parse loop ──────────────────────────────────────────────────────────

function _parse_lines(lines, filepath::String) :: Feature
    state      = _new_parse_state()
    in_feature = false

    for (lineno, raw_line) in enumerate(lines)
        line = string(raw_line)

        # ── DocString mode ────────────────────────────────────────────────────
        if state.in_docstring
            s = lstrip(line)
            if startswith(s, state.docstring_delimiter)
                # Close docstring — patch last step
                content = join(state.docstring_lines, "\n")
                ds      = DocString(state.docstring_content_type, content)
                steps   = state.current_steps
                if !isempty(steps)
                    last_step = steps[end]
                    steps[end] = Step(last_step.keyword, last_step.text,
                                      ds, last_step.datatable, last_step.line)
                end
                state.in_docstring          = false
                state.docstring_delimiter   = ""
                state.docstring_content_type = ""
                empty!(state.docstring_lines)
                state.docstring_indent      = 0
            else
                push!(state.docstring_lines, _strip_indent(line, state.docstring_indent))
            end
            continue
        end

        trimmed = strip(line)

        # Skip empty lines and full-line comments
        (isempty(trimmed) || startswith(trimmed, "#")) && continue

        # ── Tags ─────────────────────────────────────────────────────────────
        if startswith(trimmed, "@")
            append!(state.pending_tags, _parse_tags(trimmed))
            continue
        end

        # ── Feature (and aliases) ────────────────────────────────────────────
        local feat_name
        if (feat_name = _strip_keyword(line, "Feature:"))      !== nothing ||
           (feat_name = _strip_keyword(line, "Ability:"))      !== nothing ||
           (feat_name = _strip_keyword(line, "Business Need:")) !== nothing
            in_feature            = true
            state.feature_name    = feat_name
            state.feature_line    = lineno
            state.feature_tags    = copy(state.pending_tags)
            empty!(state.pending_tags)
            continue
        end

        !in_feature && continue

        # ── Rule (Gherkin 6) ─────────────────────────────────────────────────
        local rule_name
        if (rule_name = _strip_keyword(line, "Rule:")) !== nothing
            _finish_current_scenario!(state)   # flush any open background/scenario
            _finish_current_rule!(state)
            state.in_rule          = true
            state.rule_name        = rule_name
            state.rule_line        = lineno
            state.rule_tags        = copy(state.pending_tags)
            state.rule_background  = nothing
            empty!(state.pending_tags)
            empty!(state.rule_description)
            empty!(state.rule_scenarios)
            continue
        end

        # ── Background ───────────────────────────────────────────────────────
        local bg_name
        if (bg_name = _strip_keyword(line, "Background:")) !== nothing
            _finish_current_scenario!(state)
            state.current_kind = :background
            state.current_name = bg_name
            state.current_line = lineno
            empty!(state.current_description)
            empty!(state.current_steps)
            continue
        end

        # ── Scenario Outline (must be before Scenario) ────────────────────────
        local out_name
        if (out_name = _strip_keyword(line, "Scenario Outline:")) !== nothing ||
           (out_name = _strip_keyword(line, "Scenario Template:")) !== nothing
            _finish_current_scenario!(state)
            state.current_kind = :outline
            state.current_name = out_name
            state.current_line = lineno
            state.current_tags = copy(state.pending_tags)
            empty!(state.pending_tags)
            empty!(state.current_description)
            empty!(state.current_steps)
            empty!(state.current_examples)
            continue
        end

        # ── Scenario ─────────────────────────────────────────────────────────
        local sc_name
        if (sc_name = _strip_keyword(line, "Scenario:")) !== nothing
            _finish_current_scenario!(state)
            state.current_kind = :scenario
            state.current_name = sc_name
            state.current_line = lineno
            state.current_tags = copy(state.pending_tags)
            empty!(state.pending_tags)
            empty!(state.current_description)
            empty!(state.current_steps)
            continue
        end

        # ── Examples ─────────────────────────────────────────────────────────
        local ex_name
        if state.current_kind == :outline &&
           ((ex_name = _strip_keyword(line, "Examples:")) !== nothing ||
            (ex_name = _strip_keyword(line, "Scenarios:")) !== nothing)
            _finish_current_examples!(state)
            _close_open_datatable!(state)
            state.in_examples    = true
            state.examples_name  = ex_name
            state.examples_tags  = copy(state.pending_tags)
            state.examples_line  = lineno
            empty!(state.pending_tags)
            empty!(state.examples_header)
            empty!(state.examples_rows)
            continue
        end

        # ── Data table row ────────────────────────────────────────────────────
        if startswith(lstrip(line), "|")
            row = _parse_table_row(trimmed)
            if state.in_examples
                if isempty(state.examples_header)
                    state.examples_header = row
                else
                    push!(state.examples_rows, row)
                end
            else
                if !state.in_datatable
                    state.in_datatable = true
                    empty!(state.datatable_rows)
                end
                push!(state.datatable_rows, row)
            end
            continue
        else
            _close_open_datatable!(state)
        end

        # ── DocString start ───────────────────────────────────────────────────
        if _is_docstring_delimiter(line)
            delim = _docstring_delimiter_type(line)
            state.in_docstring          = true
            state.docstring_delimiter   = delim
            state.docstring_indent      = _leading_spaces(line)
            s = lstrip(line)
            after_delim = strip(s[nextind(s, length(delim)):end])
            state.docstring_content_type = after_delim
            empty!(state.docstring_lines)
            continue
        end

        # ── Step keywords ─────────────────────────────────────────────────────
        if (step_info = _detect_step_keyword(line)) !== nothing
            kw, text = step_info
            push!(state.current_steps, Step(kw, text, nothing, nothing, lineno))
            continue
        end

        # ── Free-text description ─────────────────────────────────────────────
        if state.current_kind == :none && in_feature
            if state.in_rule
                push!(state.rule_description, trimmed)
            else
                push!(state.feature_description, trimmed)
            end
        elseif state.current_kind != :none && isempty(state.current_steps) && !state.in_examples
            push!(state.current_description, trimmed)
        end
    end

    # Finalise any open structures
    _close_open_datatable!(state)
    _finish_current_rule!(state)   # also calls _finish_current_scenario! inside

    # If we never entered a Rule, we may have a dangling scenario
    if state.current_kind != :none
        _finish_current_scenario!(state)
    end

    return Feature(
        filepath,
        state.feature_name,
        join(state.feature_description, "\n"),
        state.feature_tags,
        state.background,
        state.children,
        state.feature_line
    )
end
