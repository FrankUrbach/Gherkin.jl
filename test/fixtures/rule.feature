Feature: Rule keyword support
  Demonstrates Gherkin 6 Rule blocks.

  Background:
    Given the system is initialized

  Rule: Basic arithmetic
    Background:
      Given a calculator is open

    Scenario: Addition
      When I add 2 and 3
      Then the result is 5

    @slow
    Scenario: Subtraction
      When I subtract 1 from 4
      Then the result is 3

  Rule: Edge cases

    Scenario: Zero
      When I add 0 and 0
      Then the result is 0
