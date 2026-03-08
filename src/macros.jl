# Step definition macros and hook macros

# ─── Step macros ─────────────────────────────────────────────────────────────
# All step macros are equivalent — they register into GLOBAL_REGISTRY

macro given(pattern, fn_expr)
    loc = string(__source__.file, ":", __source__.line)
    quote
        Gherkin.register!(Gherkin.GLOBAL_REGISTRY, $(esc(pattern)), $(esc(fn_expr)), $loc)
    end
end

macro when(pattern, fn_expr)
    loc = string(__source__.file, ":", __source__.line)
    quote
        Gherkin.register!(Gherkin.GLOBAL_REGISTRY, $(esc(pattern)), $(esc(fn_expr)), $loc)
    end
end

macro then(pattern, fn_expr)
    loc = string(__source__.file, ":", __source__.line)
    quote
        Gherkin.register!(Gherkin.GLOBAL_REGISTRY, $(esc(pattern)), $(esc(fn_expr)), $loc)
    end
end

macro step(pattern, fn_expr)
    loc = string(__source__.file, ":", __source__.line)
    quote
        Gherkin.register!(Gherkin.GLOBAL_REGISTRY, $(esc(pattern)), $(esc(fn_expr)), $loc)
    end
end

macro and(pattern, fn_expr)
    loc = string(__source__.file, ":", __source__.line)
    quote
        Gherkin.register!(Gherkin.GLOBAL_REGISTRY, $(esc(pattern)), $(esc(fn_expr)), $loc)
    end
end

macro but(pattern, fn_expr)
    loc = string(__source__.file, ":", __source__.line)
    quote
        Gherkin.register!(Gherkin.GLOBAL_REGISTRY, $(esc(pattern)), $(esc(fn_expr)), $loc)
    end
end

# ─── Assertion helper ─────────────────────────────────────────────────────────

"""
    @expect expr
    @expect expr msg

BDD-style assertion — equivalent to `@test`.
"""
macro expect(expr)
    quote
        Test.@test $(esc(expr))
    end
end

macro expect(expr, msg)
    quote
        Test.@test $(esc(expr))
    end
end

# ─── Per-scenario hooks ───────────────────────────────────────────────────────

"""
    @before do context ... end
    @before(["tag1", "tag2"]) do context ... end

Register a before-scenario hook (optionally filtered by tags).
"""
macro before(fn_expr)
    loc = string(__source__.file, ":", __source__.line)
    quote
        push!(Gherkin.BEFORE_HOOKS,
              Gherkin.HookDefinition(String[], $(esc(fn_expr)), $loc))
    end
end

macro before(tags_expr, fn_expr)
    loc = string(__source__.file, ":", __source__.line)
    quote
        push!(Gherkin.BEFORE_HOOKS,
              Gherkin.HookDefinition($(esc(tags_expr)), $(esc(fn_expr)), $loc))
    end
end

"""
    @after do context ... end
    @after(["tag1", "tag2"]) do context ... end

Register an after-scenario hook (optionally filtered by tags).
"""
macro after(fn_expr)
    loc = string(__source__.file, ":", __source__.line)
    quote
        push!(Gherkin.AFTER_HOOKS,
              Gherkin.HookDefinition(String[], $(esc(fn_expr)), $loc))
    end
end

macro after(tags_expr, fn_expr)
    loc = string(__source__.file, ":", __source__.line)
    quote
        push!(Gherkin.AFTER_HOOKS,
              Gherkin.HookDefinition($(esc(tags_expr)), $(esc(fn_expr)), $loc))
    end
end

# ─── Suite-level hooks ────────────────────────────────────────────────────────

"""
    @beforeall do ... end

Register a hook that runs once before any scenario in the suite.
"""
macro beforeall(fn_expr)
    quote
        push!(Gherkin.BEFORE_ALL_HOOKS, $(esc(fn_expr)))
    end
end

"""
    @afterall do ... end

Register a hook that runs once after all scenarios in the suite.
"""
macro afterall(fn_expr)
    quote
        push!(Gherkin.AFTER_ALL_HOOKS, $(esc(fn_expr)))
    end
end
