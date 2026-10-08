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
pointer hover and press feedback, and wrapped text. Home shows unfinished tasks
only. Clicking a task's text opens its source Dashboard file in Obsidian; the
separate checkbox saves its completion state.

## Completed task visibility

Completed tasks are directly hidden from Home in both Apex groups and the
current built-in tag filter. There is no completed header, count, disclosure or
expansion control. The underlying Dashboard/JSON model retains every task;
hiding never deletes or relocates stored rows. Incomplete source order is
preserved, along with the existing typography and task actions.

A row stays visible while its save is pending and hides only when the controller
applies a verified saved or reread source state. A failed save follows the actual
reloaded state instead of inventing completion. Reopening or refreshing retains
the same visibility policy. Undoing completion in Obsidian makes that task
visible after the next read. The inline Add footer, quota header and
pointer-close lifecycle remain unchanged.

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

### Completed visibility verification

Rendering regressions use synthetic built-in and Apex data with both completed
and unfinished tasks at the existing popover size in Aqua and Dark Aqua. They
exercise the production list, with completed tasks still present in storage
while Home only renders unfinished rows. The inline footer, long text and
existing group headings remain part of those scenes.

On 2026-10-08 the universal arm64/x86_64 Release build passes. The full suite
reports **176 passed, 2 existing accessibility skips, 0 failed**. Strict Swift
formatting and diff checks pass. Aqua/Dark Aqua sample images confirm there is
no completed row or disclosure taking space between unfinished groups.

Desktop status-menu navigation did not expose a usable Pulse surface through
the available automation, so live pointer/click acceptance remains a manual
check. No real Dashboard task or persisted selection is changed by these
automated checks. The earlier disclosure-specific tests are removed because
that presentation is no longer part of Home.
