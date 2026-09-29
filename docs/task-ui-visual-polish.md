# Task-first UI visual polish

Pulse keeps the Apex Dashboard as the source of truth. This pass only refines
the native macOS presentation inside the 360×510 menu-bar popover.

## Home hierarchy

The Home header contains the Pulse identity, compact Codex and 88VIP summaries,
and Settings. Pulse uses a 19-point title, a 26-point identity icon, and
7-point vertical padding. Its status controls remain clickable, but use smaller
icons and text so the task list is the primary visual element. Detailed usage
stays on the separate Usage page.

## Task list

The source Dashboard column names and order are preserved in the tab strip.
Cards use a subdued 13-point group label rather than a Dashboard-style card.
The tab strip is 32 points high including its container. Rows have a 36-point
minimum target, 15-point task text, compact spacing, and neutral hover and
press feedback. Long task text wraps inside the row.
Completed tasks use a dimmer label and small completion symbol without a
strikethrough.

Tasks remain read-only: selecting one still opens its original Dashboard file
in Obsidian. This change does not alter Apex parsing, data models, provider
refreshing, or popover hover management.

## Verification

Rendering tests load only the fictional Apex fixture and cover a dashboard
containing completed and long task text in both Aqua and Dark Aqua. Build and
unit tests validate the implementation; the final appearance and pointer
interaction need a desktop pass in the running menu-bar app.
