# Execution
1. Implement minimum guard plus presentation completion, one-shot departure scheduling and Closing cleanup.
2. Wire native show/will-close/did-close callbacks, motion preferences and duplicate request guard.
3. Extend hover lifecycle regressions; build, directed tests, full suite, formatting and diff checks.
4. Attempt desktop inspection; restart the exact old Pulse process with the new build without editing user task data.
5. Update README, interaction spec and motion notes; record actual validation and leave changes uncommitted.

## Results
- Implemented 300 ms + native show-completion guard, 180 ms one-shot departure, 50 ms geometry correction including arrow, Closing gating/cancellation and Reduce Motion handling. Layout/data logic untouched.
- Directed hover run: 19 passed. Final build/full suite: 113 total, 111 passed, 2 existing accessibility tests skipped, 0 failed. Strict formatting and diff checks passed; synthetic light/dark Home images inspected.
- Intermediate native integration runs failed while the graphical session was locked. Added test-only locked/non-console detection and a system-animation callback timeout; the final native test passed. No product delay was increased to accommodate testing.
- Trellis check review found no actionable issue. Real mouse/visual behavior remains unverified: Computer Use timed out on exact old/new application paths; bundle lookup was ambiguous.
- Stopped the exact old PulseBuiltinTasks process, launched PulsePopoverMotion, verified the new executable is running. Current Reduce Motion setting is false; system preferences not changed.
- Preserved built-in task changes and independent report (SHA-1 unchanged). No commit, push, release or real TODO edits.

## Dashboard picker follow-up
- Found direct runModal presentation from the transient popover with no app activation or native-close handoff. Extracted DashboardFilePicker to wait for didClose, activate/front an asynchronous panel, focus duplicate requests, persist through the existing controller and return to Tasks Settings after selection/cancel.
- Settings now reflects actual connection/read/parse state and explains explicit source selection; no parser/bookmark/source migration changes.
- Six new isolated picker tests passed. Combined directed picker/hover run: 25 passed. Build/full regression: 119 total, 117 passed, 2 existing accessibility skips, 0 failed. No private config or Dashboard writes during tests.
- Read-only Trellis review found no blocking issue. Updated the frontend picker handoff contract. Strict formatting/diff checks passed; independent report SHA-1 remained unchanged.
- Stopped the exact PulsePopoverMotion process and launched PulseDashboardPicker; verified the new executable. Computer Use again returned timeoutReached on the exact new application path, so actual chooser foreground visibility and live re-selection remain unverified. On returning from a chooser, the unchanged hover policy may quickly dismiss Settings if the pointer stays outside; include that in manual acceptance.
- No commit, push, release or private task/configuration modifications by verification.
