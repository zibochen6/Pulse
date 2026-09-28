# Technical Design

## Boundaries

- `App`: process entry, AppKit delegate, status item and popover ownership. Keep one status item and one popover for the process lifetime. Render the reference project's 18-point template Codex icon with an adjacent monospaced 12-point `--%` placeholder. Bundle the MIT-licensed icon resource and preserve its notice. Use `NSHostingController` for SwiftUI content.
- `Core`: `AppConfig` plus an injectable login item service. `AppConfig` owns UserDefaults persistence and exposes observed state to the UI. A small wrapper maps `SMAppService.mainApp.status` and register/unregister errors into presentation-safe states.
- `Features/Home`: `HomeView` composes the three sections and invokes an injected quit action. It does not fetch real usage or tasks.
- `UI`: only a shared section view if it reduces actual repetition; do not add an empty design system.

## State and Flow

The app creates `AppConfig` once, injects it into `HomeView`, and observes the menu bar title preference to update the status button. On opening the popover, refresh the login item status from macOS. The user's requested launch setting is persisted separately from the OS-reported status. A toggle action requests register or unregister, refreshes status, and presents an error if the operation fails. The interface must never equate a stored request with successful registration.

`SMAppService.mainApp` requires macOS 13 and may report approval needed. Keep registration synchronous on the main actor, through a protocol that tests can replace with a fake; do not alter real login items during automated tests. Errors are presented as human-readable settings feedback, with no fallback helper.

## Compatibility and Trade-offs

- Retain the generated Xcode project in Git and change `project.yml` first, then regenerate.
- Use `ObservableObject`/`@Published` because the deployment target is macOS 13; keep UI state on the main actor under Swift 6.
- Use XcodeGen unit test target with isolated UserDefaults suite. No new Swift Package or SQLite.
- Keep the no-data readout visible by default. The title preference optionally adds `Pulse` alongside the icon and readout when enabled.
- Keep icon choice explicit and local to the status presentation for now; future provider-specific icons belong to the Provider phase, after a real source selection model exists.
- Keep the app usable if login item registration fails or cannot be verified from a development build.

## Rollback

If launch item integration causes an app startup failure, isolate or disable that path while keeping status item, popover, Settings feedback, and tests working. Do not add alternative startup mechanisms.
