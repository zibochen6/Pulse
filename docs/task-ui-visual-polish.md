# Task-first UI visual polish

Pulse's task surface is the native local list. This pass only refines
the native macOS presentation inside the 360×510 menu-bar popover.

## Home hierarchy

The Home header contains the Pulse identity, compact Codex, 88VIP and
DeepSeek summaries, and Settings. Pulse uses a 19-point title, a 26-point
identity icon, and 7-point vertical padding. Its status controls remain
clickable, but use smaller icons and text so the task list is the primary
visual element. Detailed usage stays on the separate Usage page.

## Task list

The tab strip shows the saved tags in creation order — no “All” and no
“Untagged” tab; an empty vocabulary is a single “Todo” guidance tab. The tab
strip is 32 points high including its container. Rows have a 36-point minimum
target, 15-point task text, compact spacing, and neutral hover and press
feedback. Long task text wraps inside the row. Selected tabs are filled rounded
capsules with semibold text; unselected tabs are secondary text with a light
hover fill, and keyboard focus draws a shape-matched soft affordance instead of
a square ring. Completed tasks use a dimmer label, a small completion symbol
and a strikethrough, under a small “Completed” heading after the open tasks.

Selecting a task's text opens its editor; the checkbox records completion, and
repeating tasks carry a small circular-arrows marker. This change does not
alter task storage, data models, provider refreshing, or popover hover
management.

## Verification

Rendering tests cover the tag-only task surface — including completed,
repeating and long task text — in both Aqua and Dark Aqua. Build and unit tests
validate the implementation; the final appearance and pointer interaction need
a desktop pass in the running menu-bar app.
