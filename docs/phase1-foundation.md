# Phase 1 menu bar foundation

Pulse now runs as a macOS 13+ menu bar application. AppKit owns the process delegate, one `NSStatusItem`, and one transient `NSPopover`. The status item uses the bundled `CodexMenuIcon.png` from `codex-usage-status` plus an always-visible `--%` placeholder readout, set in a 12-point monospaced-digit font; this is not a real usage value. The icon is credited in [third-party notices](../THIRD_PARTY_NOTICES.md), which are also bundled with the app. An `NSHostingController` presents SwiftUI `HomeView` inside the popover. The app bundle retains `LSUIElement=YES`, so no Dock icon is intended.

## Source boundaries

| Directory | Responsibility |
| --- | --- |
| `Pulse/App` | Process entry, status button, popover lifecycle, and Quit wiring. |
| `Pulse/Core` | UserDefaults preferences and injectable login item service. |
| `Pulse/Features/Home` | Usage, Tasks, and Settings presentation. |
| `Pulse/UI` | One shared section view used by the three sections. |

Usage and Tasks show explicit unconnected placeholders. No provider, Codex, Obsidian, task parser, or database code runs in this phase.

## Preferences and system status

`AppConfig` stores `launchAtLoginRequested` and `showMenuBarLabel` in UserDefaults; both default to `false`. The second preference adds the word “Pulse” before the readout without hiding `--%`. The first value is the user's request, while `SMAppService.mainApp.status` is the actual macOS login item status. Opening the popover refreshes that status. Turning the setting on or off registers or unregisters when the system status needs a change, then refreshes the status. Registration errors and the system approval state are shown in Settings without preventing the popover from opening.

The tests inject a fake login item service and a private UserDefaults suite. They never register the test host as a real login item. Real registration may require approval in **System Settings > General > Login Items**. An unsigned development build may not behave like a stable installed release; signing and fresh-machine login-item verification belong to the release gate.

## Verify

From the repository root:

```sh
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulsePhase1DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulsePhase1DerivedData CODE_SIGNING_ALLOWED=NO test
```

Manual smoke checks: launch the built app, confirm the Codex-style icon and `--%` readout appear without a Dock icon, click to open and close the popover, click elsewhere to dismiss it, verify Usage/Tasks placeholders, then choose **Quit Pulse**. Do not use the launch-at-login toggle during automated testing; verify it separately from a stable installed build when release signing is available.

In the initial development check on macOS 27, the unsigned Debug app launched and remained running, the generated bundle reported `LSUIElement=true`, and macOS Accessibility exposed a Pulse menu bar item that accepted a click. The available computer-use provider could not read an accessibility window for this menu bar app, so visual popover, click-away, and Quit checks remain manual Xcode run checks. The six unit tests passed. Real login item registration was not changed during this check.
