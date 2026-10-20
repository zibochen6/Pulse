# Task-first UI polish

Pulse Home is the short daily view of the native local to-do list. The header
contains Pulse identity, lightweight Codex and 88VIP status buttons, and the
Settings entry. Usage details remain on the separate Usage page so the task
surface receives the available height.

The task surface has no repeated “Tasks” title or toolbar. It starts directly
with the tag tab row; Pulse refreshes the task list and re-arms daily repeats
when its popover opens.

## Task surface

Tabs are the saved tags in creation order; there is no “All” and no “Untagged”
tab, and an empty vocabulary is shown by a single “Todo” guidance tab. A task
row uses a full-width hit area, modest spacing, pointer hover and press
feedback, and wrapped text. Open tasks come first; completed tasks stay
visible after them under a small “Completed” heading. Clicking a task's text
opens its editor; the separate checkbox records completion.

## Completed rows and pending saves

Completed tasks stay visible in every tag tab — dimmed and struck through,
after the open tasks, never hidden or auto-removed. The underlying JSON model
retains every task; presentation never deletes or relocates stored rows, and
stored order is preserved. A row stays visible while its save is pending and
shows a spinner in place of the checkmark. A failed save follows the actual
reloaded state instead of inventing completion, and its inline error offers
retry. The centered quick-add footer, quota header and pointer-close lifecycle
remain unchanged.

## Popover hover lifecycle

`PopoverHoverController` owns hover dismissal and close-request state. Opening
requires a minimum 300 ms click guard and AppKit's presentation-complete signal.
After that, departure from the status item and entire popover starts one 180 ms
close delay. Returning to either region cancels the delay.

AppKit tracking events can be absent when SwiftUI changes the hosted view
hierarchy. While the popover is shown, the controller periodically compares
tracked regions with current screen geometry every 50 ms, including the arrow.
A mismatch updates state without extending an existing close deadline. Native
show/dismiss animation respects Reduce Motion and retains opaque content.
Outside clicks and status-item toggles request close without a hover delay.
Closing cancels timers and ignores re-entry; pages reset after dismissal completes.
See [motion and response](popover-motion.md) for the current lifecycle and checks.

## Validation

Unit tests cover opening protection, missing entry and exit events, delayed
close, re-entry cancellation, arrow geometry, and reset. Rendering tests
exercise the production task surface with synthetic local data — the tag-only
tab row, completed and repeating rows, and empty states — in Aqua and Dark
Aqua. The final desktop checklist remains: retain the pointer on the status
item for two seconds, enter and leave the popover, return before the close
deadline, switch tag tabs, and open Settings.

The development build was launched from `/tmp/PulseTaskFirstDerivedData`. The
available desktop automation timed out while reading this accessory-only menu
bar app, so the live menu-bar checklist requires a manual pass and is not
claimed as verified by the unit tests. Desktop status-menu navigation still
does not expose a usable Pulse surface through that automation, so live
pointer/click acceptance remains a manual check; automated checks never change
real task data.
