# Task-first popover and interaction

Pulse uses a 360×510 menu bar popover with exactly three page states: Home, Usage, and Settings. Home places the Pulse identity, a compact clickable Codex status, and the Settings gear in its header. The rest of Home is a task-list surface. Since Obsidian is not connected yet, the surface shows one compact “Obsidian not connected” row and a fixed “Connect Obsidian” entry. It shows no sample tasks, Memo tab, or Add Task control. The connection entry opens the existing Tasks explanation in Settings; no Vault is accessed.

The header status uses the same real `UsageRefreshState` and `UsageMenuFormatter` as the menu bar. One quota window shows only its percentage; multiple windows show their short duration labels. Loading, unavailable, and failure show their existing short statuses without a stale quota. The header has no reset time, update time, refresh control, or other-provider list. If actual windows exceed the available width, the summary scrolls horizontally in its bounded header area.

Clicking the status opens the Usage page. `UsageView` retains real Codex windows, percentages, reset and update times, refresh, and explicit error content. The page scrolls vertically for extra windows or long errors. Add Provider opens Settings' Providers explanation without connecting anything. Usage and Settings return to Home; closing the popover also resets page state to Home. The menu bar format, Codex fetching, and all existing settings remain unchanged.

## Pointer lifecycle

`PulseAppDelegate` owns one `NSStatusItem` and one transient `NSPopover`. Native outside clicks and a second status-item click close it immediately. `PopoverHoverController` owns only hover dismissal and has four states:

| State | Behavior |
| --- | --- |
| Closed | No hover work remains. |
| Opening | Begins before `show`; for one second, enter/exit events update observations but cannot close the panel. |
| Interactive | At the end of Opening, current button, content, and whole-window geometry is read again. A pointer over the status button or content keeps the panel open. |
| PendingClose | Once tracked hover is absent, wait 400 ms, then verify actual pointer geometry. Re-entry cancels the task; window-only hover such as the arrow retries the check. |

Every AppKit close callback resets hover and page state. The earlier hover controller scheduled a 400 ms close immediately after `show`; entry/exit events around the opening click could be stale or missing. The Opening boundary removes that premature decision. A separate same-click AppKit close/action sequence has not been observed here, so no speculative toggle suppression was added.

## Verification

Build and test with the commands in the README. Tests cover pointer states, Home/Usage/Settings page transitions and reset, compact one-window and multi-window formatting, and Aqua/Dark Aqua rendering with loading, success, unavailable, and long failure states. The rendering tests confirm an opaque 360×510 surface; native AppKit event delivery still requires desktop checks.

The desktop checklist is: click and leave the pointer on the status item for two seconds; enter content; leave both areas for at least 400 ms; re-enter before the deadline; open Usage and Settings and return; click outside; and toggle with the status item. This build launched, but Computer Use accessibility capture timed out when targeting Pulse by bundle ID and by app path. The menu bar interactions and page clicks remain unverified on a live desktop; they are not inferred from unit tests.
