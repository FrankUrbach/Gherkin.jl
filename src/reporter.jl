# Console reporter with ANSI color output

const ANSI_GREEN  = "\e[32m"
const ANSI_RED    = "\e[31m"
const ANSI_YELLOW = "\e[33m"
const ANSI_CYAN   = "\e[36m"
const ANSI_RESET  = "\e[0m"

function _step_keyword_str(kw::StepKeyword)
    kw == GivenKeyword && return "Given"
    kw == WhenKeyword  && return "When"
    kw == ThenKeyword  && return "Then"
    kw == AndKeyword   && return "And"
    kw == ButKeyword   && return "But"
    return "Step"
end

function report_step_pass(step::Step)
    kw = _step_keyword_str(step.keyword)
    println("  $(ANSI_GREEN)✓$(ANSI_RESET) $(kw) $(step.text)")
end

function report_step_fail(step::Step, err::Exception)
    kw = _step_keyword_str(step.keyword)
    println("  $(ANSI_RED)✗$(ANSI_RESET) $(kw) $(step.text)")
    println("    $(ANSI_RED)$(err)$(ANSI_RESET)")
end

function report_step_undefined(step::Step)
    kw = _step_keyword_str(step.keyword)
    println("  $(ANSI_YELLOW)?$(ANSI_RESET) $(kw) $(step.text)")
    macro_name = kw == "Given" ? "@given" : kw == "When" ? "@when" : kw == "Then" ? "@then" : "@step"
    println("    $(ANSI_YELLOW)Undefined step. Implement with:$(ANSI_RESET)")
    println("    $(ANSI_YELLOW)$(macro_name)(\"$(step.text)\") do context$(ANSI_RESET)")
    println("    $(ANSI_YELLOW)    # TODO$(ANSI_RESET)")
    println("    $(ANSI_YELLOW)end$(ANSI_RESET)")
end

function report_step_skipped(step::Step)
    kw = _step_keyword_str(step.keyword)
    println("  $(ANSI_CYAN)-(ANSI_RESET) $(kw) $(step.text)")
end

function report_scenario_start(scenario::Scenario)
    println("\n  $(ANSI_CYAN)Scenario: $(scenario.name)$(ANSI_RESET)")
end

function report_scenario_result(scenario::Scenario, passed::Bool)
    if passed
        println("  $(ANSI_GREEN)PASSED$(ANSI_RESET): $(scenario.name)")
    else
        println("  $(ANSI_RED)FAILED$(ANSI_RESET): $(scenario.name)")
    end
end

function report_feature_start(feature::Feature)
    println("\n$(ANSI_CYAN)Feature: $(feature.name)$(ANSI_RESET)")
    if !isempty(feature.description)
        for line in split(feature.description, '\n')
            println("  $(line)")
        end
    end
end

function report_feature_result(feature::Feature, passed::Int, total::Int)
    color = passed == total ? ANSI_GREEN : ANSI_RED
    println("\n$(color)$(passed)/$(total) scenarios passed$(ANSI_RESET) in Feature: $(feature.name)")
end
