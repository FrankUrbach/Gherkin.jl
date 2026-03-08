Feature: Doc strings

  Scenario: Step with a doc string
    Given a step with content
      """json
      {"key": "value"}
      """
    Then it should work

  Scenario: Step with a backtick doc string
    Given a step with content
      ```typeql
      match $x isa thing;
      ```
    Then it should work
