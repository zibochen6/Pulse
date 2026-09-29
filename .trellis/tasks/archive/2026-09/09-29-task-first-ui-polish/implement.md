# Implementation plan

1. Refine header summaries and task-list presentation in the existing Home and Tasks views.
2. Extend `PopoverHoverController` with cancellable interactive geometry reconciliation and unit tests for missed departure events.
3. Extend rendering coverage for loaded task states, long text, empty columns, and both appearances.
4. Add the task-first UI documentation and update the established pointer-lifecycle state-management specification.
5. Build, run all tests, inspect the diff, attempt the desktop interaction checklist, then commit without pushing.

## Validation

- `xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -derivedDataPath /tmp/PulseTaskFirstDerivedData build`
- `xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -derivedDataPath /tmp/PulseTaskFirstDerivedData test`
- `git diff --check`

## Rollback points

The UI changes are isolated to the Home and Tasks views. Pointer reconciliation is isolated to `PopoverHoverController`; removing that task restores the previous tracking-only behavior.
