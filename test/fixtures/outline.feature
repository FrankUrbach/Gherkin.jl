Feature: Scenario Outlines

  Scenario Outline: Adding <a> and <b>
    Given a new calculator
    When I add <a> and <b>
    Then the result is <result>

    Examples:
      | a | b | result |
      | 1 | 2 | 3      |
      | 5 | 5 | 10     |
      | 0 | 0 | 0      |
