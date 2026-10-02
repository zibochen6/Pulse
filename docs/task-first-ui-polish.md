# Task-first UI polish

Pulse Home is the short daily view of one selected Apex Dashboard. The header
contains Pulse identity, lightweight Codex and 88VIP status buttons, and the
Settings entry. Usage details remain on the separate Usage page so the task
surface receives the available height.

The task surface has no repeated “Tasks” title or toolbar. It starts directly
with the current Dashboard column tabs; Pulse reloads the selected Dashboard
when its popover opens.

## Task surface

Tabs use the Dashboard's original column names and order. Pulse does not label
a column “Today” unless its source already does: the supported Apex format has
no verified due-date semantics. Cards are small text groups rather than
Dashboard-style panels. A task row uses a full-width hit area, modest spacing,
pointer hover and press feedback, and wrapped text. Completed rows use a dim
color and a completed indicator without a heavy strikethrough. Clicking any
task still opens its source Dashboard file in Obsidian.

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
close, re-entry cancellation, arrow geometry, and reset. Rendering tests use a
fictional Apex fixture with an empty column, completed task, and wrapped task
title in Aqua and Dark Aqua. The final desktop checklist remains: retain the
pointer on the status item for two seconds, enter and leave the popover, return
before the close deadline, switch tabs, and open Settings.

The development build was launched from `/tmp/PulseTaskFirstDerivedData`. The
available desktop automation timed out while reading this accessory-only menu
bar app, so the live menu-bar checklist requires a manual pass and is not
claimed as verified by the unit tests.
