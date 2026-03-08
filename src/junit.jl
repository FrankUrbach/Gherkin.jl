# JUnit XML report writer

using Dates

"""
    _xml_escape(s) :: String

Escape characters that are invalid inside XML attribute values and text content.
"""
function _xml_escape(s::AbstractString) :: String
    s = replace(s, "&"  => "&amp;")
    s = replace(s, "<"  => "&lt;")
    s = replace(s, ">"  => "&gt;")
    s = replace(s, "\"" => "&quot;")
    s = replace(s, "'"  => "&apos;")
    # Strip ANSI escape codes that may appear in error messages
    s = replace(s, r"\e\[[0-9;]*m" => "")
    return s
end

"""
    write_junit_xml(results::RunResults, filepath::String)

Write a JUnit-compatible XML report to `filepath`.

The format is understood by Jenkins, GitLab CI, GitHub Actions, and most other
CI systems that consume JUnit XML.
"""
function write_junit_xml(results::RunResults, filepath::String)
    total_tests    = sum(length(fr.scenario_results)
                         for fr in results.feature_results; init=0)
    total_failures = sum(count(r -> r.status == :fail, fr.scenario_results)
                         for fr in results.feature_results; init=0)
    total_skipped  = sum(count(r -> r.status == :skip, fr.scenario_results)
                         for fr in results.feature_results; init=0)
    total_time     = round(results.duration_ns / 1e9, digits=3)
    timestamp      = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")

    open(filepath, "w") do io
        println(io, """<?xml version="1.0" encoding="UTF-8"?>""")
        println(io,
            """<testsuites name="Gherkin" tests="$(total_tests)" """ *
            """failures="$(total_failures)" skipped="$(total_skipped)" """ *
            """errors="0" time="$(total_time)">""")

        for fr in results.feature_results
            suite_tests    = length(fr.scenario_results)
            suite_failures = count(r -> r.status == :fail, fr.scenario_results)
            suite_skipped  = count(r -> r.status == :skip, fr.scenario_results)
            suite_time     = round(fr.duration_ns / 1e9, digits=3)
            feature_name   = _xml_escape(fr.feature.name)

            println(io,
                """  <testsuite name="$(feature_name)" tests="$(suite_tests)" """ *
                """failures="$(suite_failures)" skipped="$(suite_skipped)" """ *
                """errors="0" time="$(suite_time)" timestamp="$(timestamp)">""")

            for sr in fr.scenario_results
                sc_time   = round(sr.duration_ns / 1e9, digits=3)
                classname = _xml_escape(fr.feature.name)
                scname    = _xml_escape(sr.scenario.name)

                if sr.status == :skip
                    println(io,
                        """    <testcase name="$(scname)" classname="$(classname)" """ *
                        """time="$(sc_time)"><skipped/></testcase>""")

                elseif sr.status == :pass
                    println(io,
                        """    <testcase name="$(scname)" classname="$(classname)" """ *
                        """time="$(sc_time)"/>""")

                else  # :fail or :undefined in any step
                    failing = filter(r -> r.status in (:fail, :undefined), sr.step_results)
                    msgs = join(
                        [_xml_escape("$(r.step.text): $(r.error_message)") for r in failing],
                        "\n")
                    first_msg = isempty(failing) ? "unknown failure" :
                                _xml_escape(first(failing).error_message)
                    println(io,
                        """    <testcase name="$(scname)" classname="$(classname)" """ *
                        """time="$(sc_time)">""")
                    println(io,
                        """      <failure message="$(first_msg)">$(msgs)</failure>""")
                    println(io, """    </testcase>""")
                end
            end

            println(io, "  </testsuite>")
        end

        println(io, "</testsuites>")
    end
end
