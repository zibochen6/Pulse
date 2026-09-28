# Popover layout and interaction

Pulse keeps a 360×510 menu bar popover with Home and Settings pages. Home now follows a compact Usage area, a larger Tasks area, and a fixed Connect Obsidian action at the bottom. The Pulse header and Settings gear remain above them. Tasks uses a clear disconnected state rather than sample task rows; the bottom action opens the Tasks explanation in Settings and does not read or change a Vault. The reference task-list screenshot informed the hierarchy only. Memo and Add Task controls are absent until those features exist.

Usage displays the shared controller's real Codex quota windows, percentages, reset times, update time, refresh control, and explicit loading, unavailable, or failure messages. It has a bounded scroll area so extra windows and long errors remain accessible without pushing Tasks or the bottom action offscreen. No other-provider value is invented; Add Provider still opens the Providers explanation in Settings. Settings keeps General, Providers, Tasks, About, Back, and Quit, and retains the prior UserDefaults and Login Items behavior.

## Pointer lifecycle

`PulseAppDelegate` owns one `NSStatusItem` and one transient `NSPopover`. Native outside clicks and a second status-item click still close it immediately. `PopoverHoverController` owns only hover dismissal and has four states:

| State | Behavior |
| --- | --- |
| Closed | No hover work remains. |
| Opening | Begins before `show`; for one second, enter/exit events update observations but cannot close the panel. |
| Interactive | At the end of Opening, current button, content, and whole-window geometry is read again. A pointer over the status button or content keeps the panel open. |
| PendingClose | Once tracked hover is absent, wait 400 ms, then verify actual pointer geometry. Re-entry cancels the task; window-only hover such as the arrow retries the check. |

Every AppKit close callback resets both tasks and hover state. The earlier controller scheduled a 400 ms close immediately after `show`; entry/exit events around the opening click could be stale or missing, so it could mistake a held pointer for departure. The new Opening boundary removes that premature decision. The controller has no method that reopens the popover. A separate same-click AppKit close/action sequence has **not** been observed in this environment, so the status-item action was not given speculative suppression logic. If flicker remains on a real desktop, capture the close callback and button action order for one physical click before changing toggle handling.

## Verification

Run the build and test commands in the README. Tests exercise Opening protection and geometry resampling, PendingClose, re-entry cancellation, window-only hover, and reset after AppKit-style dismissal. Home and Settings render in Aqua and Dark Aqua; Home also renders loading, one or more quota windows, unavailable, and a long failure message. These tests verify state decisions and an opaque 360×510 surface, but they cannot deliver native status-button or transient-popover events.

Interactive desktop checks remain necessary: click while holding the pointer on the status item for two seconds, enter content, leave both regions for at least 400 ms, re-enter before the deadline, navigate to Settings and back, click outside, and click the status item again. The menu-bar-only app could not be inspected through the available Computer Use session: Pulse and SystemUIServer accessibility capture timed out. Those desktop event paths are therefore unverified here; no actual duplicate click sequence or confirmed root cause beyond the premature hover scheduling is claimed.
