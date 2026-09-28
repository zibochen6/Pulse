# Design: task-first popover

## Current boundaries

`PulseAppDelegate` owns one status item, transient popover, shared `UsageController`, and `AppConfig`. `HomeView` currently owns local Settings destination state and renders detailed `UsageView` inside Home. `UsageMenuFormatter` already implements the desired one-window and multi-window compact labels; it also distinguishes loading, unavailable, and failure. `SettingsView` scrolls to its existing destination sections. `TasksView` currently centers a large disconnected state.

## Page and data flow

Keep AppKit as the popover lifecycle owner. Use one small `@MainActor` observable page state with exactly `home`, `usage`, and `settings(SettingsDestination)` cases, not a stack. `HomeView` composes those pages and receives the same shared config and usage controller. The popover close delegate resets the page to Home without changing hover timing. Usage and Settings back actions also set Home. Add Provider from Usage opens Settings' Providers explanation; its Back returns Home.

The Home header composes Pulse identity, `AIStatusSummary`, and the gear button. `AIStatusSummary` consumes the shared usage state and the existing bundled Codex icon. Reuse `UsageMenuFormatter` for the compact value so Home and the macOS status item agree on one vs multiple windows; leave the AppKit menu bar consumer untouched. The summary is a button with an accessible label and navigates to Usage. It renders no quota metadata or provider placeholders. Keep the value on one line in a bounded, horizontally scrollable area when many actual windows exceed the available width.

Usage is a separate page with a back/title header and a vertically scrollable `UsageView`. Keep `UsageView`'s existing real values and Add Provider explanation action; do not alter fetch or refresh semantics. Settings retains its General, Providers, Tasks, and About sections.

The task region owns a title, a list-shaped main surface, a compact disconnected row, and Connect Obsidian action. It should remain ready to accept real rows later without pretending tasks exist today. Avoid large centered icon/empty-state treatments. The Connect action navigates to Settings' Tasks section and performs no Vault access.

## Compatibility and validation

Keep 360×510 sizing, opaque adaptive background, `NSPopover` behavior, and all existing preference keys. Do not add a UserDefaults key or selection UI for quota windows. Add targeted tests for compact formatting and page reset/navigation, render Home/Usage/Settings in Aqua and Dark Aqua with single/multiple/loading/error states, and verify long Usage content remains accessible. Build and run all existing tests. Native menu bar interactions require a desktop attempt; if the accessibility tool cannot inspect them, report that limit without claiming a pass.
