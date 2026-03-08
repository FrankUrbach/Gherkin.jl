Feature: Data tables

  Scenario: Step with a data table
    Given the following users:
      | name  | age |
      | Alice | 30  |
      | Bob   | 25  |
    Then there are 2 users
