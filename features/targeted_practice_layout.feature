Feature: Cleaner targeted practice on Linux

  @SCN-001 @REQ-001
  Scenario: Find targeted practice without collection clutter
    Given the Linux practice screen is open
    Then targeted practice is available at the top
    And a collection enable or disable control is available in the footer
    And the collection explanation, separate status text, and clear-data control are not persistently displayed in the practice area

  @SCN-002 @REQ-001 @REQ-003
  Scenario: Recover an unknown collection state
    Given the collection state cannot be determined
    When the user accesses collection settings
    Then the interface does not claim collection is enabled or disabled
    And the user can retry loading the collection state

  @SCN-003 @REQ-002
  Scenario: Accept consent from targeted practice
    Given collection is disabled
    When the user selects targeted practice
    Then a consent dialog explains the local aggregate data collected and that exact typed text is not stored
    And the dialog explains that pattern data can be cleared
    When the user accepts consent
    Then collection is not shown as enabled until the engine confirms it
    And targeted practice starts automatically after the engine confirms collection is enabled

  @SCN-004 @REQ-002
  Scenario: Cancel consent from targeted practice
    Given collection is disabled
    When the user selects targeted practice and cancels consent
    Then collection remains disabled
    And targeted practice does not start

  @SCN-005 @REQ-002
  Scenario: Enable collection from the footer
    Given collection is disabled
    When the user enables collection from the footer and accepts consent
    Then collection is shown as enabled only after the engine confirms it
    And targeted practice does not start automatically

  @SCN-006 @REQ-002 @REQ-003
  Scenario: Collection enabling fails
    Given collection is disabled
    When the user accepts consent and enabling collection fails
    Then the collection error and recovery are accessible in a dialog
    And collection is not shown as enabled
    And targeted practice does not start

  @SCN-007 @REQ-001
  Scenario: Practice with insufficient pattern data
    Given collection is enabled and there is insufficient pattern data
    When the user starts targeted practice
    Then the practice screen explains that ordinary words are being used

  @SCN-008 @REQ-003
  Scenario: Clear pattern data from targeted practice
    Given collection is enabled and pattern data and history exist
    When the user clears pattern data from the targeted-practice experience
    Then pattern data is cleared
    And collection remains enabled
    And history remains unchanged

  @SCN-009 @REQ-003
  Scenario: Clearing pattern data fails
    Given pattern data exists
    When the user attempts to clear pattern data and the operation fails
    Then the collection error is accessible in a dialog
    And the interface does not report that the data was cleared

  @SCN-010 @REQ-003
  Scenario: Disable collection without deleting data
    Given collection is enabled and pattern data exists
    When the user disables collection from the footer and the engine confirms it
    Then collection is disabled
    And pattern data and history remain unchanged

  @SCN-011 @REQ-003
  Scenario: A critical typing error occurs
    Given the practice screen is open
    When an unrelated critical error prevents typing
    Then the error remains visible in the practice area

  @SCN-012 @REQ-004
  Scenario: Operate and dismiss the dialog with a keyboard
    Given a collection dialog is open during practice
    When the user operates and cancels the dialog using the keyboard
    Then focus is visible in the dialog
    And keystrokes do not reach the underlying practice session while the dialog is open
    And practice focus is usable after the dialog closes

  @SCN-013 @REQ-001 @REQ-004
  Scenario: Use collection controls in constrained presentation
    Given the Linux practice screen uses a narrow window or a high-contrast theme
    When the user accesses the collection dialog
    Then the controls, messages, and fallback explanation when present are readable and reachable
