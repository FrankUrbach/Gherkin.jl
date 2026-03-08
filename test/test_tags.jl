@testset "Tags" begin
    fixtures = joinpath(@__DIR__, "fixtures")

    # Helper: build a minimal registry with a no-op "a step"
    function _tag_reg()
        reg = StepRegistry()
        register!(reg, "a step", (ctx) -> nothing, "test:1")
        return reg
    end

    @testset "Tags are parsed from feature file" begin
        f = parse_feature(joinpath(fixtures, "tagged.feature"))
        @test any(t -> t.name == "suite", f.tags)

        scenarios = expand_scenarios(f)
        @test length(scenarios) == 3

        fast_sc = scenarios[1]
        @test any(t -> t.name == "fast", fast_sc.tags)

        slow_sc = scenarios[2]
        @test any(t -> t.name == "slow", slow_sc.tags)
        @test any(t -> t.name == "wip",  slow_sc.tags)

        untagged_sc = scenarios[3]
        @test isempty(untagged_sc.tags)
    end

    @testset "_effective_tags includes feature-level tags" begin
        f = parse_feature(joinpath(fixtures, "tagged.feature"))
        scenarios = expand_scenarios(f)

        eff = Gherkin._effective_tags(scenarios[1], f)
        @test "suite" in eff   # from feature
        @test "fast"  in eff   # from scenario
    end

    @testset "include_tags filters in only matching scenarios" begin
        f   = parse_feature(joinpath(fixtures, "tagged.feature"))
        reg = _tag_reg()

        fr = run_feature(f, reg; include_tags=["fast"])
        results = fr.scenario_results

        @test length(results) == 3                          # all 3 recorded
        @test results[1].status == :pass                    # @fast → runs
        @test results[2].status == :skip                    # @slow @wip → skipped
        @test results[3].status == :skip                    # untagged   → skipped
    end

    @testset "exclude_tags filters out matching scenarios" begin
        f   = parse_feature(joinpath(fixtures, "tagged.feature"))
        reg = _tag_reg()

        fr = run_feature(f, reg; exclude_tags=["wip"])
        results = fr.scenario_results

        @test results[1].status == :pass    # @fast — kept
        @test results[2].status == :skip    # @wip  — excluded
        @test results[3].status == :pass    # untagged — kept
    end

    @testset "feature-level tag is honoured in include_tags" begin
        f   = parse_feature(joinpath(fixtures, "tagged.feature"))
        reg = _tag_reg()

        # "suite" is on the feature → all scenarios inherit it
        fr = run_feature(f, reg; include_tags=["suite"])
        results = fr.scenario_results
        @test all(r -> r.status == :pass, results)
    end

    @testset "no tag filters → all scenarios run" begin
        f   = parse_feature(joinpath(fixtures, "tagged.feature"))
        reg = _tag_reg()

        fr = run_feature(f, reg)
        @test all(r -> r.status == :pass, fr.scenario_results)
    end

    @testset "tagged @before hook only fires for matching scenarios" begin
        reg = StepRegistry()
        register!(reg, "a step", (ctx) -> nothing, "test:1")

        fired = String[]
        Gherkin.reset_hooks!()
        push!(Gherkin.BEFORE_HOOKS,
              HookDefinition(["fast"], (ctx) -> push!(fired, "fast-hook"), "test"))

        f = parse_feature(joinpath(fixtures, "tagged.feature"))
        for sc in expand_scenarios(f)
            run_scenario(sc, nothing, reg; feature=f)
        end

        @test count(==("fast-hook"), fired) == 1   # only the @fast scenario
        Gherkin.reset_hooks!()
    end

    @testset "@beforeall and @afterall run once per suite" begin
        order = String[]

        Gherkin.reset_hooks!()
        push!(Gherkin.BEFORE_ALL_HOOKS, () -> push!(order, "beforeall"))
        push!(Gherkin.AFTER_ALL_HOOKS,  () -> push!(order, "afterall"))

        reg = _tag_reg()
        f1  = parse_feature(joinpath(fixtures, "tagged.feature"))

        # Simulate what runspec does (without file discovery)
        for fn in Gherkin.BEFORE_ALL_HOOKS; fn(); end
        run_feature(f1, reg)
        for fn in Gherkin.AFTER_ALL_HOOKS;  fn(); end

        @test order == ["beforeall", "afterall"]
        Gherkin.reset_hooks!()
    end
end
