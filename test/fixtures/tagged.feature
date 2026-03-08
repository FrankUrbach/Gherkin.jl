@suite
Feature: Tagged scenarios

  @fast
  Scenario: Fast scenario
    Given a step

  @slow @wip
  Scenario: Slow work-in-progress
    Given a step

  Scenario: Untagged scenario
    Given a step
