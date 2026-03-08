Feature: Basic calculator

  Background:
    Given a new calculator

  Scenario: Adding two numbers
    When I add 3 and 4
    Then the result is 7

  Scenario: Subtracting numbers
    When I subtract 2 from 10
    Then the result is 8
