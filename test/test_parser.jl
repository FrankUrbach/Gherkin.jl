@testset "Parser" begin
    fixtures = joinpath(@__DIR__, "fixtures")

    @testset "Basic feature" begin
        f = parse_feature(joinpath(fixtures, "basic.feature"))
        @test f.name == "Basic calculator"
        @test length(f.scenarios) == 2
        @test f.background !== nothing
        @test length(f.background.steps) == 1
        @test f.background.steps[1].text == "a new calculator"
        @test f.background.steps[1].keyword == GivenKeyword
    end

    @testset "Scenario names and steps" begin
        f = parse_feature(joinpath(fixtures, "basic.feature"))
        sc1 = f.scenarios[1]
        @test sc1 isa Scenario
        @test sc1.name == "Adding two numbers"
        @test length(sc1.steps) == 2
        @test sc1.steps[1].keyword == WhenKeyword
        @test sc1.steps[1].text == "I add 3 and 4"
        @test sc1.steps[2].keyword == ThenKeyword
        @test sc1.steps[2].text == "the result is 7"

        sc2 = f.scenarios[2]
        @test sc2.name == "Subtracting numbers"
        @test sc2.steps[1].text == "I subtract 2 from 10"
        @test sc2.steps[2].text == "the result is 8"
    end

    @testset "Tags" begin
        f = parse_feature(joinpath(fixtures, "tags.feature"))
        @test length(f.tags) == 1
        @test f.tags[1].name == "smoke"

        sc1 = f.scenarios[1]
        @test length(sc1.tags) == 1
        @test sc1.tags[1].name == "fast"

        sc2 = f.scenarios[2]
        @test length(sc2.tags) == 2
        tag_names = Set(t.name for t in sc2.tags)
        @test "slow" in tag_names
        @test "integration" in tag_names
    end

    @testset "Doc strings" begin
        f = parse_feature(joinpath(fixtures, "docstrings.feature"))
        sc1 = f.scenarios[1]
        step = sc1.steps[1]
        @test step.docstring !== nothing
        @test step.docstring.content_type == "json"
        @test contains(step.docstring.content, "\"key\": \"value\"")

        sc2 = f.scenarios[2]
        step2 = sc2.steps[1]
        @test step2.docstring !== nothing
        @test step2.docstring.content_type == "typeql"
        @test contains(step2.docstring.content, "match")
    end

    @testset "Data tables" begin
        f = parse_feature(joinpath(fixtures, "datatable.feature"))
        sc = f.scenarios[1]
        step = sc.steps[1]
        @test step.datatable !== nothing
        @test length(step.datatable) == 3   # header + 2 rows
        @test step.datatable[1] == ["name", "age"]
        @test step.datatable[2] == ["Alice", "30"]
        @test step.datatable[3] == ["Bob", "25"]
    end

    @testset "Scenario Outline" begin
        f = parse_feature(joinpath(fixtures, "outline.feature"))
        @test length(f.scenarios) == 1
        outline = f.scenarios[1]
        @test outline isa ScenarioOutline
        @test outline.name == "Adding <a> and <b>"
        @test length(outline.examples) == 1
        ex = outline.examples[1]
        @test ex.header == ["a", "b", "result"]
        @test length(ex.rows) == 3
        @test ex.rows[1] == ["1", "2", "3"]
        @test ex.rows[2] == ["5", "5", "10"]
        @test ex.rows[3] == ["0", "0", "0"]
    end

    @testset "Comments are ignored" begin
        content = """
        Feature: With comments
          # This is a comment
          Scenario: No comment steps
            # Comment inside scenario
            Given a step
            # Another comment
            Then another step
        """
        f = parse_feature_string(content)
        @test length(f.scenarios) == 1
        @test length(f.scenarios[1].steps) == 2
    end

    @testset "Empty lines ignored" begin
        content = """

        Feature: With empty lines


          Scenario: Spaced out


            Given a step


            Then another step

        """
        f = parse_feature_string(content)
        @test f.name == "With empty lines"
        @test length(f.scenarios) == 1
        @test length(f.scenarios[1].steps) == 2
    end

    @testset "Feature description" begin
        content = """
        Feature: A feature with description
          This is a description
          that spans multiple lines

          Scenario: A scenario
            Given a step
        """
        f = parse_feature_string(content)
        @test contains(f.description, "This is a description")
        @test contains(f.description, "that spans multiple lines")
    end

    @testset "Star (*) step keyword" begin
        content = """
        Feature: Star steps
          Scenario: Using star
            * first step
            * second step
            Given a given step
        """
        f = parse_feature_string(content)
        steps = f.scenarios[1].steps
        @test length(steps) == 3
        @test steps[1].keyword == StarKeyword
        @test steps[1].text == "first step"
        @test steps[2].keyword == StarKeyword
        @test steps[3].keyword == GivenKeyword
    end

    @testset "Feature keyword aliases" begin
        for kw in ("Ability:", "Business Need:")
            content = """
            $(kw) My feature
              Scenario: A scenario
                Given a step
            """
            f = parse_feature_string(content)
            @test f.name == "My feature"
            @test length(f.scenarios) == 1
        end
    end

    @testset "Rule keyword (Gherkin 6)" begin
        f = parse_feature(joinpath(fixtures, "rule.feature"))
        @test f.name == "Rule keyword support"
        @test f.background !== nothing

        # Two Rule children
        rules = [c for c in f.children if c isa Rule]
        @test length(rules) == 2

        r1 = rules[1]
        @test r1.name == "Basic arithmetic"
        @test r1.background !== nothing
        @test length(r1.background.steps) == 1
        @test length(r1.scenarios) == 2
        @test r1.scenarios[1].name == "Addition"
        @test r1.scenarios[2].name == "Subtraction"
        @test r1.scenarios[2].tags[1].name == "slow"

        r2 = rules[2]
        @test r2.name == "Edge cases"
        @test r2.background === nothing
        @test length(r2.scenarios) == 1

        # all_scenarios flattens rules
        all_sc = all_scenarios(f)
        @test length(all_sc) == 3

        # top_level_scenarios returns only non-Rule scenarios
        @test isempty(top_level_scenarios(f))
    end

    @testset "And and But keywords" begin
        content = """
        Feature: And But test
          Scenario: Multi-step
            Given first step
            And second step
            But third step
            When fourth step
            Then fifth step
            And sixth step
        """
        f = parse_feature_string(content)
        steps = f.scenarios[1].steps
        @test length(steps) == 6
        @test steps[1].keyword == GivenKeyword
        @test steps[2].keyword == AndKeyword
        @test steps[3].keyword == ButKeyword
        @test steps[4].keyword == WhenKeyword
        @test steps[5].keyword == ThenKeyword
        @test steps[6].keyword == AndKeyword
    end
end
