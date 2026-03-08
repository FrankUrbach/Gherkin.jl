# Tag Expression Language
#
# Grammar (standard boolean expression with precedence):
#   expr     → or_expr
#   or_expr  → and_expr  ('or'  and_expr)*
#   and_expr → not_expr  ('and' not_expr)*
#   not_expr → 'not' not_expr | atom
#   atom     → '(' expr ')' | TAG
#
# Tags may optionally include a leading '@'; it is stripped during tokenisation.
# Keywords 'and', 'or', 'not' are case-insensitive.

# ─── AST ─────────────────────────────────────────────────────────────────────

abstract type TagExpr end

"""Matches any scenario (used for an empty / missing expression)."""
struct TagAll     <: TagExpr end

"""Matches scenarios that have `name` in their effective tag set."""
struct TagLiteral <: TagExpr; name::String; end

"""Logical NOT."""
struct TagNot     <: TagExpr; expr::TagExpr; end

"""Logical AND (left AND right)."""
struct TagAnd     <: TagExpr; left::TagExpr; right::TagExpr; end

"""Logical OR (left OR right)."""
struct TagOr      <: TagExpr; left::TagExpr; right::TagExpr; end

# ─── Tokeniser ────────────────────────────────────────────────────────────────

const _KEYWORDS = Set(["and", "or", "not"])

function _tokenize(expr::AbstractString) :: Vector{String}
    tokens = String[]
    i = firstindex(expr)
    while i <= lastindex(expr)
        c = expr[i]
        if isspace(c)
            i = nextind(expr, i)
            continue
        end
        if c == '(' || c == ')'
            push!(tokens, string(c))
            i = nextind(expr, i)
            continue
        end
        # Tag name or keyword: starts with @, letter, or underscore
        if c == '@' || isletter(c) || c == '_'
            j = i
            # consume characters valid in a tag / keyword
            while j <= lastindex(expr)
                ch = expr[j]
                if ch == '@' || isletter(ch) || isdigit(ch) || ch in ('_', '-', '.')
                    j = nextind(expr, j)
                else
                    break
                end
            end
            raw = expr[i:prevind(expr, j)]
            # Strip leading '@'
            name = startswith(raw, "@") ? raw[nextind(raw, 1):end] : raw
            # Lowercase for keyword detection, but preserve case for tag names
            lower = lowercase(name)
            if lower in _KEYWORDS
                push!(tokens, lower)   # normalise keyword to lowercase
            else
                push!(tokens, name)    # preserve original case for tag name
            end
            i = j
            continue
        end
        # Unknown character — skip
        i = nextind(expr, i)
    end
    return tokens
end

# ─── Recursive-descent parser ─────────────────────────────────────────────────

mutable struct _TagParser
    tokens::Vector{String}
    pos::Int
end

_peek(p::_TagParser)  = p.pos <= length(p.tokens) ? p.tokens[p.pos] : nothing
_consume!(p::_TagParser) = (tok = p.tokens[p.pos]; p.pos += 1; tok)

function _parse_or(p::_TagParser) :: TagExpr
    left = _parse_and(p)
    while _peek(p) == "or"
        _consume!(p)
        right = _parse_and(p)
        left  = TagOr(left, right)
    end
    return left
end

function _parse_and(p::_TagParser) :: TagExpr
    left = _parse_not(p)
    while _peek(p) == "and"
        _consume!(p)
        right = _parse_not(p)
        left  = TagAnd(left, right)
    end
    return left
end

function _parse_not(p::_TagParser) :: TagExpr
    if _peek(p) == "not"
        _consume!(p)
        return TagNot(_parse_not(p))
    end
    return _parse_atom(p)
end

function _parse_atom(p::_TagParser) :: TagExpr
    tok = _peek(p)
    tok === nothing && error("Unexpected end of tag expression")
    if tok == "("
        _consume!(p)
        expr = _parse_or(p)
        _peek(p) == ")" || error("Expected closing ')'")
        _consume!(p)
        return expr
    end
    tok in ("and", "or", "not", ")") &&
        error("Expected a tag name but got: $(tok)")
    _consume!(p)
    return TagLiteral(tok)
end

# ─── Public API ───────────────────────────────────────────────────────────────

"""
    parse_tag_expr(expr::String) :: TagExpr

Parse a boolean tag expression string into a `TagExpr` AST.

# Examples
```julia
parse_tag_expr("@smoke")
parse_tag_expr("not @wip")
parse_tag_expr("@smoke and @fast")
parse_tag_expr("(@smoke or @fast) and not @wip")
parse_tag_expr("")   # → TagAll() — matches everything
```
"""
function parse_tag_expr(expr::AbstractString) :: TagExpr
    isempty(strip(expr)) && return TagAll()
    p = _TagParser(_tokenize(expr), 1)
    result = _parse_or(p)
    p.pos <= length(p.tokens) &&
        error("Unexpected token in tag expression: '$(p.tokens[p.pos])'")
    return result
end

"""
    eval_tag_expr(expr::TagExpr, tags::Set{String}) :: Bool

Evaluate `expr` against the given set of tag names (without `@` prefix).
"""
function eval_tag_expr(expr::TagExpr, tags::Set{String}) :: Bool
    expr isa TagAll     && return true
    expr isa TagLiteral && return expr.name in tags
    expr isa TagNot     && return !eval_tag_expr(expr.expr, tags)
    expr isa TagAnd     && return eval_tag_expr(expr.left, tags) &&
                                  eval_tag_expr(expr.right, tags)
    expr isa TagOr      && return eval_tag_expr(expr.left, tags) ||
                                  eval_tag_expr(expr.right, tags)
    return false
end
