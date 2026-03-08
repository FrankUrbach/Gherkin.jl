@smoke
Feature: Tagged feature

  @fast
  Scenario: A tagged scenario
    Given a step

  @slow @integration
  Scenario: Another tagged scenario
    Given a step
    And another step
