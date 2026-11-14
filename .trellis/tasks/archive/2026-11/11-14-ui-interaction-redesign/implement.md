# Execution plan

The user approved planning and implementation. One integrated task with parallel ownership:

1. Window/settings/integration lane: App files, HomeView, UsageView, Settings features; relevant navigation/menu/window/update tests. Own app lifecycle, connection state, settings window and update preflight.
2. Tag lane: Features/Tasks/Local, native drag bridge, task/tag interaction and rendering tests. Own shared tag manager and draft protection; coordinate signatures with window lane.
3. Visual lane: UI tokens/styles/controls, Home provider components except HomeView, interaction-hold model/tests. Coordinate AppDelegate listeners and tag drag holds with owners.
4. Root regenerates project after structural edits, coordinates integration/build. One final owner localizes resources and remaining strings, creates isolated real-view demo fixtures and assets.
5. Full tests and Release build, independent trellis-check, fixes, spec/doc sync, visual inspection and native interaction attempt. Do not equate render/test success with actual mouse/IME acceptance. Preserve user untracked files. Commit only according to workflow/user authorization.

## Verification
- xcodegen generate (root only)
- xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/PulseRedesignDerivedData CODE_SIGNING_ALLOWED=NO test
- xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/PulseRedesignDerivedData CODE_SIGNING_ALLOWED=NO build
- swift-format lint if available; no new dependencies.
- Validate light/dark × en/zh, missing/failed provider states, large amounts, 100 tags, duplicate/delete/draft guards, native IME/undo, menu/drag overlapping holds, updater cancelled install and cross-window state.
- Promotion screenshots and 15–20s demonstration use isolated fixtures, actual views/interactions and sample-data label. Record exact runtime checks and limitations.
