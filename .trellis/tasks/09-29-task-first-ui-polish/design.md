# Design: task-first UI and reliable hover dismissal

## Change boundary

The behavior gap lives in the Home task presentation and in `PopoverHoverController`'s interactive-state observations. The view layer formats existing models; the hover controller decides when departure should close the existing AppKit popover. The parser, task controller, usage controller, and providers remain untouched.

## Home presentation

`HomeView` retains its existing header and keeps the two clickable summaries. The summaries use a lighter text-first presentation without card-style backgrounds. `TasksView` continues to own loaded, loading, and connection states. Its loaded path keeps source-order column tabs, then a scrollable list of lightweight card sections and full-width task buttons. The UI derives no aliases, dates, or data values from task text.

## Pointer lifecycle

The controller continues to own Closed, Opening, Interactive, and PendingClose. Tracking callbacks remain fast observations. During Opening they cannot dismiss. While Interactive or PendingClose, a cancellable periodic reconciliation samples current pointer geometry and updates the two tracked-region flags. If current geometry is outside both, normal pending-close scheduling applies; if it is inside either, an outstanding close is cancelled. The pending-close deadline retains its final geometry check. `reset()` cancels opening, close, and reconciliation tasks.

This closes the gap where a missing AppKit `mouseExited` event leaves `overStatusButton` or `overContent` true forever. Geometry remains authoritative only for correction; tracking callbacks still provide immediate response.

## Compatibility

No public model or service interface changes. The status item, usage detail page, Apex source mapping, and Obsidian opener behave as before.
