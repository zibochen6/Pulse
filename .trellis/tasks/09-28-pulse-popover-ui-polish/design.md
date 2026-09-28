# Technical design

## Interaction ownership

Keep `PulseAppDelegate` as the sole AppKit owner and `.transient` for immediate outside-click dismissal. `PopoverHoverController` centrally owns hover closure states: closed, opening, interactive, and pending close. The delegate forwards status-button/content enter and exit plus show/close lifecycle events; SwiftUI views never close the popover directly. Opening starts before `show` and lasts 1,000 ms. Exit events update observed hover flags but cannot schedule close during Opening. At guard expiry, re-read actual button and whole popover-window geometry; if outside both, begin the normal 400 ms pending close. Entry cancels the pending close. The delegate resets the controller on every close, including AppKit-driven dismissal and explicit toggle.

The current hover controller cannot reopen the popover, so investigate the status-button action and transient close callback ordering during desktop reproduction. Keep one status-button action per user click; if the same physical click closes and triggers another open, suppress that duplicate action in the AppKit entry point using the observed click sequence. Do not add a global event tap or weaken outside-click behavior speculatively. Remove any temporary trace before commit.

## Home composition

Retain the 360×510 popover and existing Pulse brand/gear. Home uses a fixed compact top Usage area, flexible Tasks body, and fixed bottom Connect Obsidian action. Avoid the current two equal card treatment on Home while leaving Settings styling intact. The task body presents a clear disconnected state, not fake rows. Usage retains real Codex window/reset/update detail, refresh and error messages; multiple windows or longer copy may scroll in the content region instead of clipping. There are no Memo or Add Task controls until those features exist.

## Tests and compatibility

Keep the shared `UsageController` and `AppConfig` contracts, `LSUIElement`, and macOS 13/Swift 6 settings. Use focused state-machine tests with controlled timing/geometry for Opening, a held pointer, pending-close cancellation and reset; include duplicate status click behavior if reproduction confirms that path. Verify Home proportions and light/dark rendering with available view tests and visual review, including multiple quota windows and error copy. Run full build/test/lint. Record any desktop interaction paths that cannot be observed rather than claiming them as verified.
