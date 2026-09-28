# Technical design

## Boundaries and data flow

Keep one `PulseAppDelegate`-owned `NSStatusItem`, `NSPopover`, `AppConfig`, and `UsageController`. The status title continues to derive only from `UsageRefreshState`. SwiftUI Home and Settings observe the existing shared objects; UI navigation is local, transient view state and does not enter UserDefaults. No provider or task model changes are needed.

## SwiftUI layout

`HomeView` owns a small page selection and renders either Home or Settings within the same opaque 360×510 surface. Home uses a header with the existing waveform symbol, a gear button, compact section labels and content. `UsageView` switches from a large number card to quota rows and metadata while preserving every data state and refresh action. A `TasksView` displays the disconnected state; its layout can later hold real rows. `SettingsView` holds existing toggles/status/error copy, coming-soon explanations, version, bundled third-party notices, and Quit. Add Provider and Connect Obsidian route to Settings and reveal their respective explanatory section. No fake provider or task values are added.

## Popover interaction

Keep `.transient` so AppKit retains outside-click behavior. Attach `NSTrackingArea` with `.mouseEnteredAndExited`, `.activeAlways`, and `.inVisibleRect` to the status button and the popover hosting view. The delegate tracks which region the pointer occupies and owns one cancelable 400 ms close task. Entering either region cancels it; exiting schedules only when neither is occupied. On show, initialize from the current pointer location. Before timer dismissal, check current screen coordinates against the status button and popover window to guard against stale event ordering. `NSPopoverDelegate` clears pending state on any close, including system-driven closure. Do not add a global event tap or change the Codex refresh loop.

## Compatibility and failure behavior

Remain on macOS 13 and Swift 6, keep `LSUIElement=YES`, the current menu icon, and opaque adaptive surfaces. Missing notice or version metadata produces an honest fallback message. Login Items failures remain visible on Settings and never block the popover. The popover can still close immediately on an outside click through AppKit's transient behavior.

## Validation

Test pointer state transitions independently from AppKit events and retain manual checks of the actual 400 ms delay and tracking geometry. Render both pages in light and dark modes. Run the complete unit suite and Debug build. Inspect the final diff for provider changes and generated project consistency.
