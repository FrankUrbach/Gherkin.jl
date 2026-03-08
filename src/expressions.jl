# Cucumber Expressions and Regex pattern matching

struct StepPattern
    regex::Regex
    param_types::Vector{Type}  # one per capture group
    original::Union{String, Regex}
end

# Map of named parameter types to (regex_fragment, Julia type)
const PARAM_TYPES = Dict{String, Tuple{String, Type}}(
    "string"  => ("""(?:"([^"]*)")|(?:'([^']*)')""", String),
    "int"     => ("""-?[0-9]+""", Int),
    "float"   => ("""-?[0-9]*\\.[0-9]+""", Float64),
    "word"    => ("""[^\\s]+""", String),
    "bool"    => ("""true|false""", Bool),
    ""        => (""".+""", String),   # anonymous {}
)

"""
    compile_pattern(s::String) :: StepPattern

Compile a Cucumber Expression string into a StepPattern.
Supports {string}, {int}, {float}, {word}, {bool}, {}, {name}.
"""
function compile_pattern(s::String) :: StepPattern
    param_types = Type[]
    # We'll build the regex by scanning for {param} tokens
    result = IOBuffer()
    write(result, "^")
    i = firstindex(s)
    while i <= lastindex(s)
        c = s[i]
        if c == '{'
            # Find closing brace
            j = findnext(isequal('}'), s, nextind(s, i))
            if j === nothing
                # No closing brace — treat as literal
                write(result, Regex.escape(string(c)))
                i = nextind(s, i)
                continue
            end
            param_name = s[nextind(s, i):prevind(s, j)]
            if haskey(PARAM_TYPES, param_name)
                frag, typ = PARAM_TYPES[param_name]
                if param_name == "string"
                    # Special case: two capture groups in alternation, we want one value
                    # We wrap in a non-capturing group around the alternation
                    # and use a custom approach: replace double-group with single
                    write(result, """(?:"([^"]*)")|(?:'([^']*)')""")
                    push!(param_types, String)
                else
                    write(result, "(", frag, ")")
                    push!(param_types, typ)
                end
            else
                # Unknown param name → match .+, String
                write(result, "(.+)")
                push!(param_types, String)
            end
            i = nextind(s, j)
        elseif c in ('(', ')', '[', ']', '.', '*', '+', '?', '^', '$', '|', '\\')
            # Escape regex metacharacters
            write(result, "\\", c)
            i = nextind(s, i)
        else
            write(result, c)
            i = nextind(s, i)
        end
    end
    write(result, "\$")
    regex_str = String(take!(result))
    return StepPattern(Regex(regex_str), param_types, s)
end

"""
    compile_pattern(r::Regex) :: StepPattern

Wrap a Regex as a StepPattern. All capture groups yield String parameters.
"""
function compile_pattern(r::Regex) :: StepPattern
    # Count capture groups by compiling and inspecting
    # We don't have direct access to group count, so we do a test match
    # with an empty-ish string and count groups from the regex source
    n = _count_capture_groups(r.pattern)
    param_types = fill(String, n)
    return StepPattern(r, param_types, r)
end

# Count the number of capture groups in a regex pattern string
# (non-capturing groups (?:...) are excluded)
function _count_capture_groups(pattern::String) :: Int
    count = 0
    i = firstindex(pattern)
    while i <= lastindex(pattern)
        c = pattern[i]
        if c == '\\'
            # Skip escaped character
            i = nextind(pattern, i)
            if i <= lastindex(pattern)
                i = nextind(pattern, i)
            end
        elseif c == '('
            # Check if it's a non-capturing group: (?
            next_i = nextind(pattern, i)
            if next_i <= lastindex(pattern) && pattern[next_i] == '?'
                # non-capturing group or lookahead/lookbehind — don't count
                i = nextind(pattern, i)
            else
                count += 1
                i = nextind(pattern, i)
            end
        else
            i = nextind(pattern, i)
        end
    end
    return count
end

"""
    match_step(pattern::StepPattern, text::String) :: Union{Nothing, Vector{Any}}

Match a step text against a pattern. Returns nothing if no match,
or a vector of typed captured values.
"""
function match_step(pattern::StepPattern, text::String) :: Union{Nothing, Vector{Any}}
    m = match(pattern.regex, text)
    if m === nothing
        return nothing
    end
    captures = m.captures
    # Filter out nothing captures (from {string} alternation groups)
    actual_captures = filter(x -> x !== nothing, captures)

    params = Any[]
    types = pattern.param_types

    for (idx, val) in enumerate(actual_captures)
        if idx <= length(types)
            T = types[idx]
            push!(params, _convert_param(T, val))
        else
            push!(params, val)
        end
    end
    return params
end

function _convert_param(::Type{Int}, s::AbstractString)
    return parse(Int, s)
end

function _convert_param(::Type{Float64}, s::AbstractString)
    return parse(Float64, s)
end

function _convert_param(::Type{Bool}, s::AbstractString)
    return s == "true"
end

function _convert_param(::Type{String}, s::AbstractString)
    return String(s)
end

function _convert_param(T::Type, s::AbstractString)
    return String(s)
end
