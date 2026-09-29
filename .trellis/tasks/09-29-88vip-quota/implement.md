# Implementation plan: 88VIP quota

1. Add testable Keychain and 88API transport abstractions, typed response decoding, metric normalization, error mapping, and unit tests.
2. Extend shared usage metrics and stale-refresh scheduling without changing Codex formatting or its 60-second refresh loop.
3. Add the 88VIP provider controller and its lifecycle wiring in the app delegate, including popover-open stale checks.
4. Bundle the popover-only 88VIP icon, render the compact header item, add Usage detail, and add Settings credential controls.
5. Update provider and README documentation, regenerate the Xcode project if source/resource registration requires it, and run build plus unit tests.

## Validation

- `xcodegen generate`
- `xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug build`
- `xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug test`
- Review the staged diff for Keychain leakage, icon licensing notice, and unchanged Codex status-bar behavior.

## Risk points

- Preserve decimal precision and convert cents once.
- Keep `UsageController` isolated per provider so a 88VIP failure cannot affect Codex.
- Do not include API keys in test fixtures, request diagnostics, errors, or documentation.
