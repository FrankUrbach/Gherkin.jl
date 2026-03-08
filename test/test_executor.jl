@testset "Executor" begin
    fixtures = joinpath(@__DIR__, "fixtures")

    @testset "expand_outline" begin
        f = parse_feature(joinpath(fixtures, "outline.feature"))
        outline = f.scenarios[1]
        @test outline isa ScenarioOutline
        scenarios = expand_outline(outline)
        @test length(scenarios) == 3

        sc1 = scenarios[1]
        @test sc1 isa Scenario
        @test contains(sc1.name, "Example 1")
        @test sc1.steps[1].text == "a new calculator"
        @test sc1.steps[2].text == "I add 1 and 2"
        @test sc1.steps[3].text == "the result is 3"

        sc2 = scenarios[2]
        @test sc2.steps[2].text == "I add 5 and 5"
        @test sc2.steps[3].text == "the result is 10"

        sc3 = scenarios[3]
        @test sc3.steps[2].text == "I add 0 and 0"
        @test sc3.steps[3].text == "the result is 0"
    end

    @testset "ScenarioContext" begin
        ctx = ScenarioContext()
        ctx[:value] = 42
        @test ctx[:value] == 42
        ctx["name"] = "hello"
        @test ctx["name"] == "hello"
        @test ctx[:name] == "hello"
        @test haskey(ctx, :value)
        @test haskey(ctx, "name")
        @test !haskey(ctx, :missing)
        @test get(ctx, :missing, 99) == 99
        @test get(ctx, "value", 0) == 42
    end

    @testset "StepRegistry — basic registration and lookup" begin
        reg = StepRegistry()
        register!(reg, "a new calculator", (ctx) -> nothing, "test:1")
        register!(reg, "I add {int} and {int}", (ctx, a, b) -> nothing, "test:2")

        defn, params = find_step(reg, "a new calculator")
        @test defn.location == "test:1"
        @test isempty(params)

        defn2, params2 = find_step(reg, "I add 3 and 4")
        @test params2 == [3, 4]
    end

    @testset "UndefinedStep exception" begin
        reg = StepRegistry()
        @test_throws UndefinedStep find_step(reg, "no matching step")
    end

    @testset "AmbiguousStep exception" begin
        reg = StepRegistry()
        register!(reg, "I do something", (ctx) -> nothing, "a:1")
        register!(reg, "I do something", (ctx) -> nothing, "b:2")
        @test_throws AmbiguousStep find_step(reg, "I do something")
    end

    @testset "run_scenario — result type and pass/fail" begin
        reg = StepRegistry()
        register!(reg, "a new calculator", function(ctx)
            ctx[:result] = 0
        end, "test:1")
        register!(reg, "I add {int} and {int}", function(ctx, a, b)
            ctx[:result] = a + b
        end, "test:2")
        register!(reg, "the result is {int}", function(ctx, expected)
            @test ctx[:result] == expected
        end, "test:3")
        register!(reg, "I subtract {int} from {int}", function(ctx, a, b)
            ctx[:result] = b - a
        end, "test:4")

        f = parse_feature(joinpath(fixtures, "basic.feature"))
        scenarios = expand_scenarios(f)
        @test length(scenarios) == 2

        r1 = run_scenario(scenarios[1], f.background, reg)
        @test r1 isa ScenarioResult
        @test r1.status == :pass
        @test passed(r1)
        @test r1.duration_ns >= 0

        r2 = run_scenario(scenarios[2], f.background, reg)
        @test r2.status == :pass
    end

    @testset "run_scenario outline expansion" begin
        reg = StepRegistry()
        register!(reg, "a new calculator", (ctx) -> (ctx[:result] = 0), "t:1")
        register!(reg, "I add {int} and {int}", (ctx, a, b) -> (ctx[:result] = a + b), "t:2")
        register!(reg, "the result is {int}", function(ctx, expected)
            @test ctx[:result] == expected
        end, "t:3")

        f = parse_feature(joinpath(fixtures, "outline.feature"))
        for sc in expand_scenarios(f)
            r = run_scenario(sc, f.background, reg)
            @test r.status == :pass
        end
    end

    @testset "Before and after hooks — HookDefinition" begin
        reg = StepRegistry()
        register!(reg, "a step", (ctx) -> nothing, "test:1")

        hook_log = String[]
        before_fn = (ctx) -> push!(hook_log, "before")
        after_fn  = (ctx) -> push!(hook_log, "after")

        Gherkin.reset_hooks!()
        push!(Gherkin.BEFORE_HOOKS, HookDefinition(String[], before_fn, "test:0"))
        push!(Gherkin.AFTER_HOOKS,  HookDefinition(String[], after_fn,  "test:0"))

        scenario = Scenario("test", "", Tag[],
                            [Step(GivenKeyword, "a step", nothing, nothing, 1)], 1)
        r = run_scenario(scenario, nothing, reg)
        @test r.status == :pass
        @test hook_log == ["before", "after"]
        Gherkin.reset_hooks!()
    end

    @testset "Step with docstring is passed extra arg" begin
        reg = StepRegistry()
        received_docstring = Ref{Union{DocString,Nothing}}(nothing)
        register!(reg, "a step with content", function(ctx, ds::DocString)
            received_docstring[] = ds
        end, "test:1")
        register!(reg, "it should work", (ctx) -> nothing, "test:2")

        f = parse_feature(joinpath(fixtures, "docstrings.feature"))
        r = run_scenario(expand_scenarios(f)[1], f.background, reg)
        @test r.status == :pass
        @test received_docstring[] !== nothing
        @test received_docstring[].content_type == "json"
        @test contains(received_docstring[].content, "\"key\": \"value\"")
    end

    @testset "Step with data table is passed extra arg" begin
        reg = StepRegistry()
        received_table = Ref{Union{DataTable,Nothing}}(nothing)
        register!(reg, "the following users:", function(ctx, tbl::DataTable)
            received_table[] = tbl
        end, "test:1")
        register!(reg, "there are {int} users", function(ctx, n)
            @test n == 2
        end, "test:2")

        f = parse_feature(joinpath(fixtures, "datatable.feature"))
        r = run_scenario(expand_scenarios(f)[1], f.background, reg)
        @test r.status == :pass
        @test received_table[] !== nothing
        @test received_table[][1] == ["name", "age"]
        @test length(received_table[]) == 3
    end
end
