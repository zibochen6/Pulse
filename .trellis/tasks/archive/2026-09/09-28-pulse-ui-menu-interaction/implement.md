# Implementation checklist

1. Confirm current source, tests, XcodeGen project, and relevant frontend state guidelines; use a fresh `codex/` branch from the clean checkout.
2. Refactor Home composition and Usage density. Add a Tasks empty-state view and a separate in-popover Settings view. Keep settings and usage wiring on existing shared objects.
3. Add AppKit pointer tracking and delayed dismissal with explicit cancellation/reset. Retain transient outside-click handling and status item toggle.
4. Add focused hover state and page rendering tests. Regenerate `Pulse.xcodeproj` with XcodeGen for new Swift files.
5. Update README and add `docs/ui-layout-refactor.md` with layout, interaction, future extension, and actual validation limits.
6. Run Swift formatting/lint if configured, `xcodebuild ... build`, `xcodebuild ... test`, and practical runtime smoke checks for menu/pointer/UI behavior. Fix only verified issues.
7. Review `git diff`, ensure provider internals did not change, capture durable conventions in Trellis spec, commit `refactor: redesign Pulse menu layout and interactions`, and do not push.
