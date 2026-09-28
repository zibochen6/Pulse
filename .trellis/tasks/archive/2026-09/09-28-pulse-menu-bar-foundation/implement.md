# Implementation Checklist

1. Read project specs and Phase 0 architecture docs; confirm current source, XcodeGen, SDK, and test target pattern.
2. Move the existing entry/delegate to `App`; implement the status button with the reference Codex icon plus `--%` readout, one transient popover, SwiftUI hosting, and Quit. Bundle the icon resource and preserve its MIT attribution.
3. Add `AppConfig` and injectable `SMAppService.mainApp` wrapper in `Core`; wire status refresh and menu bar title preference to the app and Settings UI.
4. Build `HomeView` Usage/Tasks/Settings placeholders using small reusable UI only where helpful.
5. Add XcodeGen unit test target and focused config/status tests; regenerate the checked-in project.
6. Update README, add `docs/phase1-foundation.md`, record the prior menu bar iteration in `docs/08-menu-bar-status-requirements.md`, and update roadmap terminology and launch-at-login placement.
7. Build and test with `xcodebuild`; smoke launch the app; review source/docs consistency, Git diff and status.
8. Perform Trellis quality/spec review, commit with the requested message, and report remaining verification limits.

## Validation

- `xcodegen generate`
- `xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulsePhase1DerivedData CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulsePhase1DerivedData CODE_SIGNING_ALLOWED=NO test`
- Launch the built `.app` and verify the visible Codex icon plus `--%` readout, popover, dismissal, Dock absence, Quit where the host GUI allows it.
- `git diff --check`, inspect complete diff and untracked files.

## Risk Points

- `PulseAppDelegate` is the existing startup path; losing its lifetime would leave the app inert.
- XcodeGen regeneration must include moved files and the test target.
- Login item tests must use a fake to avoid altering the host's login settings.
