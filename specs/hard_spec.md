# Hard Spec: Cleaner targeted practice on Linux

## Adversarial Pre-Mortem
- A compact interface hides the meaning of consent or starts collecting before the user agrees or the engine confirms the setting.
- Moving errors into a dialog makes failed operations invisible, leaving users believing collection or deletion succeeded.
- A modal steals typing focus or lets keystrokes reach the underlying practice session.

## Hidden Assumptions
- Targeted practice remains opt-in and existing local pattern data and history retain their current semantics.
- The targeted-practice entry point can provide access to clearing data without adding persistent controls above the prompt.
- The existing engine protocol supports these interactions without changes.

## Alternatives Considered
| Approach | Reason Rejected |
|----------|----------------|
| Keep all explanations and controls above the prompt | Continues to crowd the practice area. |
| Put all explanations and controls in the footer | Moves the clutter rather than keeping the footer compact. |

## Summary
Simplify the Linux practice screen by keeping a targeted-practice entry point at the top, placing a compact collection enable/disable control in the footer, and presenting consent and collection-related details and errors in a modal.

## Requirements

### REQ-001: Compact practice layout
**Description:** Keep the targeted-practice entry point at the top and the collection enable/disable control in the footer; remove the persistent collection explanation, status text, and clear-data control from the practice area.
**Acceptance Criteria:**
- The targeted-practice entry point remains usable whether collection is enabled or disabled.
- The footer control offers enabling or disabling collection as appropriate without a separate status panel.
- The ordinary-words fallback explanation remains visible when targeted practice has insufficient data.
**Edge Cases:** Unknown collection state must not be represented as enabled or disabled; recovery remains accessible. Controls remain reachable at narrow window sizes.
**Out of Scope:** Redesigning unrelated practice controls or the macOS client.

### REQ-002: Explicit consent
**Description:** Show consent before enabling collection, whether initiated from targeted practice or the footer.
**Acceptance Criteria:**
- The modal explains that local aggregate counts of expected letters and pairs are stored, not exact typed text, and that data can be cleared.
- Cancel does not enable collection or start targeted practice.
- Accept requests enabling; the interface represents collection as enabled only after engine confirmation.
- After confirmation, a targeted-practice-initiated consent flow starts targeted practice automatically; footer-initiated consent does not start it.
**Edge Cases:** A failed or unavailable enable request does not start targeted practice or claim success; its error and recovery are accessible in the modal.
**Out of Scope:** Changing engine consent or storage semantics.

### REQ-003: Targeted-practice data and errors
**Description:** Provide access to clearing pattern data within the targeted-practice experience and show collection-related errors in a modal.
**Acceptance Criteria:**
- Users can clear pattern data from the targeted-practice experience without a persistent clear button in the main practice area.
- Clearing pattern data preserves history and the collection-enabled setting.
- Collection errors are accessible in a modal; critical errors preventing typing remain visible in the practice area.
- Failed operations do not report success.
**Edge Cases:** An unavailable collection status offers a retry; failed clearing preserves an honest error state. Unrelated engine errors must not be hidden as collection errors.
**Out of Scope:** Deleting typing history or automatically deleting data when collection is disabled.

### REQ-004: Accessible modal interaction
**Description:** Keep the modal usable without interfering with practice input.
**Acceptance Criteria:**
- Users can operate and cancel the modal with the keyboard, with visible focus.
- Keystrokes do not reach the underlying practice session while the modal is open; closing it restores usable practice focus.
**Edge Cases:** Modal controls and messages remain readable and reachable at narrow window sizes and in high-contrast themes.
**Out of Scope:** A general accessibility redesign.

## Open Questions
- None blocking; placement of the clear action inside the targeted-practice experience is an implementation detail subject to review.

## Trade-offs
- A modal interrupts the first targeted session, but keeps informed consent and error recovery out of the persistent practice layout.
- A compact footer provides less detail at a glance; the modal must make relevant information discoverable.

## Risk Level
Medium — the UI changes touch opt-in consent, asynchronous engine responses, deletion, and keyboard focus, while preserving existing storage and engine contracts.
