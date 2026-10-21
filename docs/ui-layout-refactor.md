# Task-first popover and interaction

Pulse uses a 360×380 menu bar popover with exactly three page states: Home, Usage, and Settings. Home opens with a lightweight toolbar — the Pulse identity on the leading edge, flexible space, then the Settings gear — followed by a separate quota strip carrying the compact clickable Codex, 88VIP, and DeepSeek statuses. The strip is its own band below the toolbar, so header height never depends on how long the amounts are, and the surface keeps its fixed size while content changes. The rest of Home is the task-list surface: the native local to-do list — a tag-tab row, the task list, and a left-aligned `+ Add task` row that expands the inline composer in place. Task density and fonts remain unchanged by the motion update.

The Codex header status uses the same real `UsageRefreshState` and `UsageMenuFormatter` as the menu bar. One quota window shows only its percentage; multiple windows show their short duration labels. Loading, unavailable, and failure show their existing short statuses without a stale quota. The strip has no reset time, update time, refresh control, or other-provider list. It sits below the toolbar at the 14-point leading inset, so brand and Settings stay on their own row no matter how long an amount is. Each control shows the provider name above the value in monospaced digits, and the provider layout measures each control and wraps complete controls into further rows without shrinking type or truncating decimal digits. Only an individual readout wider than the full usable row gets a bounded horizontal scroll area.

Clicking any provider status requests its own fresh reading and opens the Usage page. `UsageView` retains real Codex windows, percentages, reset and update times, refresh, and explicit error content. The page also shows independent 88VIP and DeepSeek balance sections, each with refresh and update state. DeepSeek retains CNY/USD totals separately; the compact summary prefers CNY. The page scrolls vertically for extra windows or long errors. Providers settings contains separate SecureFields backed by distinct Keychain accounts. Saving, replacing, or removing a key clears form text on success, invalidates older fetches, and requests fresh data without affecting other providers. Add Provider opens Settings' Providers explanation without connecting anything. Usage and Settings return to Home; closing the popover also resets page state to Home. The menu bar format, Codex fetching, and all existing settings remain unchanged.

## Pointer lifecycle

`PulseAppDelegate` owns one `NSStatusItem` and one transient `NSPopover`. Native outside clicks and a second status-item click request close immediately, without a hover delay. `PopoverHoverController` manages these lifecycle states:

| State | Behavior |
| --- | --- |
| Closed | No hover work remains. |
| Opening | Begins before `show`; a minimum 300 ms protection and `popoverDidShow` must both complete before hover dismissal is allowed. |
| Interactive | At the end of Opening, current button, content, and whole-window geometry is read again. A pointer over the status button or content keeps the panel open. |
| PendingClose | Once all regions are empty, wait 180 ms, then verify actual geometry. Re-entry cancels; duplicate exits do not extend the deadline. |
| Closing | Cancel all timers. Ignore tracking, stale show callbacks and repeated close/open requests until native dismissal completes. |

`popoverWillClose` stops hover work; `popoverDidClose` resets the page after animation, preventing a page flash during dismissal. Opening still protects against stale click events. Every 50 ms, actual button/content/window geometry repairs missing tracking events, including over the arrow. Native motion is enabled with the existing opaque background and disabled when the system requests Reduce Motion. No custom window-size animation is used; macOS controls its exact effect and duration.

## Verification

Build and test with the commands in the README. Tests cover pointer states, Home/Usage/Settings page transitions and reset, compact one-window and multi-window formatting, and Aqua/Dark Aqua rendering with loading, success, unavailable, and long failure states. DeepSeek tests cover loading, CNY/USD, missing-key, authentication, rate-limit, network, timeout and malformed-response states in both appearances. Anchor measurements assert actual non-overlapping provider/Settings frames within 360 points, complete amount widths, leading alignment and whole-control wrapping for multiple quota windows and large balances. Representative PNGs and frame JSON are generated under `/tmp/PulseDeepSeekRender`. The rendering tests confirm an opaque fixed 360×380 surface, a quota strip laid out below the toolbar, the task list at the height the popover actually leaves for it, a pending completion that does not move the row, and a visible tag selection plate; native AppKit event delivery still requires desktop checks.

The desktop checklist is: retain the pointer on the clicked status item for two seconds; enter content; leave both areas and check a short 180 ms grace before native dismissal; re-enter before the deadline; open Usage and Settings; edit a task; click outside; and toggle with the status item. See [motion verification](popover-motion.md) for current results and unverified live interactions.
