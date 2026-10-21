# Task-first UI visual polish

Pulse's task surface is the native local list. This pass only refines
the native macOS presentation inside the 360×380 menu-bar popover.

## Home hierarchy

Home opens with a lightweight toolbar: the Pulse identity (a 12-point waveform
in a 22-point mark beside a 15-point semibold title) on the leading edge,
flexible space, then a 28-point Settings gear. 6 points of top and 4 points of
bottom padding frame it. Directly below, on its own band, the quota strip
carries compact Codex, 88VIP and DeepSeek summaries, each showing its provider
name above the current value so a long balance widens only its own control.
Because the strip is separate, the header height does not change with the
amounts and the task list always gets the same region. Its status controls stay
clickable and use smaller icons and text so the task list remains the primary
visual element. Detailed usage stays on the separate Usage page.

## Task list

The tab strip shows the saved tags in creation order — no “All” and no
“Untagged” tab; an empty vocabulary is a single “Todo” guidance tab. The tab
strip is 32 points high including its container. Rows have a 36-point minimum
target, 15-point task text, compact spacing, and neutral hover and press
feedback. Long task text wraps inside the row. Selected tabs are filled rounded
capsules with semibold text; the accent plate slides between pills instead of
cross-fading, unselected tabs are secondary text with a light hover fill, and
keyboard focus draws a shape-matched soft affordance instead of a square ring.
The list ends with a left-aligned “+ Add task” row that expands the composer in
place rather than a floating centered button. Completed tasks use a dimmer
label and a strikethrough, in place, with no separate heading above them.

Selecting a task's text opens its editor; the checkbox records completion, and
repeating tasks carry a small circular-arrows marker. A save still in flight
shows a small pending indicator in place of the checkmark without changing the
row's geometry, so the completion animation has a stable target. This change does not
alter task storage, data models, provider refreshing, or popover hover
management.

## Verification

Rendering tests cover the tag-only task surface — including completed,
repeating and long task text — in both Aqua and Dark Aqua — plus the same
states at the height the popover actually leaves the list, a pending completion
that must not move its row, and the painted tag selection plate. Build and unit
tests validate the implementation; the final appearance and pointer interaction
need a desktop pass in the running menu-bar app.
