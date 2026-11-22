# Targeted practice: live client checks

Run separately on a real supported Linux/Quickshell setup and on macOS, with
isolated test state. Do not use personal history. Record the platform, display
size, steps, result and any untested scenario. No screenshots or logs should be
shared without reviewing them for private information.

1. Open targeted practice with no consent. Decline; confirm no collection and no
   targeted session starts. Accept on a later attempt; verify collection is
   shown as enabled only after the core confirms the save.
2. Start targeted practice with empty data. Verify the visible explanation that
   ordinary words are being used; complete practice and verify a later targeted
   run reflects learned patterns after enough observations.
3. Clear pattern data; confirm collection remains enabled, history remains
   unchanged, and a new targeted run shows the insufficient-data explanation.
4. With an isolated state path made unwritable, try enabling and clearing.
   Confirm an error is visible and neither action claims success. Restore test
   state and verify saved consent and learning were not falsely changed.
5. Disable collection during practice, make errors, complete the run, and
   re-enable it. Confirm those later attempts did not change recommendations.
6. Operate the controls and consent dialog with keyboard alone. Verify focus is
   visible, decline is possible without accepting, and input cannot leak into
   the underlying typing session while a dialog is open.
7. Repeat at a narrow window size and with a high-contrast theme. Verify labels,
   controls, fallback and errors are readable, not clipped, and reachable.

The source-level client checks and the QML routing test do not establish the
macOS event wiring, real desktop focus, layout, or contrast behavior.
