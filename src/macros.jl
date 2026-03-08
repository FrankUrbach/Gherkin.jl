# Step definition macros and hook macros

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

# Assertion helper — BDD style @expect, equivalent to @test
macro expect(expr)
    quote
        Test.@test $(esc(expr))
    end
end

macro expect(expr, msg)
    quote
        Test.@test $(esc(expr)) broken=false
        if !($(esc(expr)))
            @error $msg
        end
    end
end

# Hook macros
macro before(fn_expr)
    quote
        push!(Gherkin.BEFORE_HOOKS, $(esc(fn_expr)))
    end
end

macro after(fn_expr)
    quote
        push!(Gherkin.AFTER_HOOKS, $(esc(fn_expr)))
    end
end
