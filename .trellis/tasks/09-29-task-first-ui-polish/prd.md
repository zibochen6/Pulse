# Polish task-first UI and restore popover hover behavior

## Goal

Make Pulse a daily AI task launcher: Home prioritizes the selected Apex Dashboard's tasks, and the menu bar popover stays open while the pointer is over the status item or its content, then closes reliably after departure.

## Confirmed facts

- Home has a fixed 360×510 surface with Home, Usage, and Settings pages.
- `TasksView` already renders the Apex data model and `PopoverHoverController` owns hover dismissal.
- Dashboard columns have no verified date semantics, so tabs retain their source titles and order.
- The provider and parser layers are out of scope.

## Requirements

- Reduce the visual prominence of the clickable Codex and 88VIP summaries while retaining their existing detail-page navigation.
- Keep Tasks as the dominant Home region. Improve tabs, card grouping, task-row spacing, complete-row styling, wrapping, and pointer feedback without changing task data or task actions.
- Retain the one-second Opening protection and 400 ms departure delay. Correct stale hover state when AppKit tracking events are absent after the popover becomes interactive.
- Keep close scheduling centralized in `PopoverHoverController`; reset all dismissal work when AppKit closes the popover.
- Add a task-first UI and hover behavior document, and update the relevant state-management contract.

## Out of scope

- Providers, Codex retrieval, Apex parsing, task writeback, date filtering, file watching, databases, and navigation changes.

## Acceptance criteria

- [ ] Home shows Tasks as the primary surface; header status remains compact and opens Usage details.
- [ ] Column tabs retain original Apex names and order. Long task text wraps, completed tasks are subdued without a strong strikethrough, and a task row has visible hover and pressed feedback.
- [ ] A pointer kept on the clicked status item survives Opening; departure from both regions closes after about 400 ms; re-entry cancels closing; stale tracked hover cannot keep the popover open once current geometry is outside.
- [ ] Opening protection, event loss correction, pending-close cancellation, reset, pages, long tasks, empty columns, and Aqua/Dark Aqua render paths have automated coverage.
- [ ] Build, unit tests, diff check, and desktop validation are run or any unavailable desktop checks are documented.
