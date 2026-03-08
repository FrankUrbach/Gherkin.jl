@testset "JUnit XML" begin

    # Build mock RunResults without running actual features, so no @test calls
    # pollute the outer testset.

    function _mock_step(text="a step")
        Step(GivenKeyword, text, nothing, nothing, 1)
    end

    function _mock_passing_results()
        s1 = Step(GivenKeyword, "I add 3 and 4",   nothing, nothing, 2)
        s2 = Step(ThenKeyword,  "the result is 7",  nothing, nothing, 3)
        sc1 = Scenario("Adding two numbers",  "", Tag[], [s1, s2], 2)
        sc2 = Scenario("Subtracting numbers", "", Tag[], [s1, s2], 3)
        feat = Feature("calc.feature", "Basic calculator", "", Tag[], nothing,
                       FeatureChild[sc1, sc2], 1)
        sr1 = ScenarioResult(sc1, :pass,
                             [StepResult(s1, :pass, "", 10_000),
                              StepResult(s2, :pass, "", 10_000)], 20_000)
        sr2 = ScenarioResult(sc2, :pass,
                             [StepResult(s1, :pass, "", 10_000),
                              StepResult(s2, :pass, "", 10_000)], 20_000)
        fr = FeatureResult(feat, [sr1, sr2], 40_000)
        RunResults([fr], 40_000)
    end

    function _mock_failing_results()
        step = _mock_step("a failing step")
        sc   = Scenario("Fails", "", Tag[], [step], 2)
        feat = Feature("fail.feature", "Failing", "", Tag[], nothing,
                       FeatureChild[sc], 1)
        sr   = ScenarioResult(sc, :fail,
                              [StepResult(step, :fail, "intentional failure", 5_000)],
                              5_000)
        fr   = FeatureResult(feat, [sr], 5_000)
        RunResults([fr], 5_000)
    end

    function _mock_skipped_results()
        step  = _mock_step()
        sc_pass = Scenario("Fast scenario",   "", [Tag("fast")], [step], 2)
        sc_skip = Scenario("Slow scenario",   "", [Tag("slow")], [step], 3)
        feat  = Feature("tagged.feature", "Tagged scenarios", "", [Tag("suite")], nothing,
                        FeatureChild[sc_pass, sc_skip], 1)
        sr_pass = ScenarioResult(sc_pass, :pass, [StepResult(step, :pass, "", 0)], 0)
        sr_skip = ScenarioResult(sc_skip, :skip, StepResult[], 0)
        fr   = FeatureResult(feat, [sr_pass, sr_skip], 0)
        RunResults([fr], 0)
    end

    function _mock_special_char_results()
        step = _mock_step("a step with <special> & \"chars\"")
        sc   = Scenario("Uses <special> & characters", "", Tag[], [step], 2)
        feat = Feature("escape.feature", "XML & escaping", "", Tag[], nothing,
                       FeatureChild[sc], 1)
        sr   = ScenarioResult(sc, :pass, [StepResult(step, :pass, "", 0)], 0)
        fr   = FeatureResult(feat, [sr], 0)
        RunResults([fr], 0)
    end

    # ─────────────────────────────────────────────────────────────────────────

    @testset "write_junit_xml produces valid XML file" begin
        tmp_path = tempname() * ".xml"
        try
            write_junit_xml(_mock_passing_results(), tmp_path)
            @test isfile(tmp_path)
            xml = read(tmp_path, String)
            @test startswith(xml, """<?xml version="1.0" encoding="UTF-8"?>""")
            @test contains(xml, "<testsuites")
            @test contains(xml, "<testsuite")
            @test contains(xml, "<testcase")
            @test contains(xml, "</testsuites>")
        finally
            isfile(tmp_path) && rm(tmp_path)
        end
    end

    @testset "passed scenarios produce self-closing testcase elements" begin
        tmp_path = tempname() * ".xml"
        try
            write_junit_xml(_mock_passing_results(), tmp_path)
            xml = read(tmp_path, String)
            @test contains(xml, "/>")
            @test !contains(xml, "<failure")
        finally
            isfile(tmp_path) && rm(tmp_path)
        end
    end

    @testset "failed scenario produces <failure> element" begin
        tmp_path = tempname() * ".xml"
        try
            write_junit_xml(_mock_failing_results(), tmp_path)
            xml = read(tmp_path, String)
            @test contains(xml, "<failure")
            @test contains(xml, "intentional failure")
        finally
            isfile(tmp_path) && rm(tmp_path)
        end
    end

    @testset "skipped scenario produces <skipped/> element" begin
        tmp_path = tempname() * ".xml"
        try
            write_junit_xml(_mock_skipped_results(), tmp_path)
            xml = read(tmp_path, String)
            @test contains(xml, "<skipped/>")
        finally
            isfile(tmp_path) && rm(tmp_path)
        end
    end

    @testset "XML special characters are escaped" begin
        tmp_path = tempname() * ".xml"
        try
            write_junit_xml(_mock_special_char_results(), tmp_path)
            xml = read(tmp_path, String)
            @test contains(xml, "&amp;")
            @test contains(xml, "&lt;")
            @test contains(xml, "&gt;")
        finally
            isfile(tmp_path) && rm(tmp_path)
        end
    end

    @testset "testsuite attributes are correct" begin
        tmp_path = tempname() * ".xml"
        try
            write_junit_xml(_mock_passing_results(), tmp_path)
            xml = read(tmp_path, String)
            @test contains(xml, "tests=\"2\"")
            @test contains(xml, "failures=\"0\"")
            @test contains(xml, "skipped=\"0\"")
        finally
            isfile(tmp_path) && rm(tmp_path)
        end
    end

    @testset "_xml_escape handles all special chars" begin
        @test Gherkin._xml_escape("a & b")        == "a &amp; b"
        @test Gherkin._xml_escape("<tag>")         == "&lt;tag&gt;"
        @test Gherkin._xml_escape("\"quote\"")     == "&quot;quote&quot;"
        @test Gherkin._xml_escape("it's")          == "it&apos;s"
        # ANSI escape codes are stripped
        @test Gherkin._xml_escape("\e[32mgreen\e[0m") == "green"
    end
end
