# Native panel and Settings interaction

This document describes the native menu-bar panel and Settings window.

## Surfaces and navigation

The menu-bar panel is 400 points wide and has a 520-point height cap.
The date, recording, focus, copy and Settings controls sit above the task list.
Both task sources shrink to fit short lists. Long lists scroll inside the task
area with Add and the AI services entry in view. Settings
opens in one independent 720 × 560 native window. Reopening Settings restores the
last category; contextual configuration actions open the relevant provider.
Cmd+, opens Settings, Cmd+W closes its window, and closing it never quits Pulse.

The AI services button opens an overview of enabled providers. Selecting a
configured provider shows its detail and refresh action. Missing credentials
lead to that provider in Settings. Back returns to the overview and then Home.
Home restores the task selection and drafts. Closing the panel resets quick
navigation and retains Settings and draft state. Pulse runs from the menu bar.

## Information and visual hierarchy

The adaptive panel uses 16-point horizontal insets, soft paper and tag colors,
and native transparency when enabled. Provider cards keep their identity colors
in the overview and detail. The single Home summary normally shows the current
Codex window and remaining quota. A service that needs attention takes priority.

Codex and Gemini quota windows have separate percentages, reset times and
progress bars in detail. Balance details show amounts in each original currency,
and 88VIP includes reported allowance, usage and expiry. Failures and missing
values get explicit status. Successful readings include their update time.
Refresh provides in-place feedback and rejects duplicate requests.

Settings shows only one category at a time. Credential forms expand on request;
Manage connection reveals Save and verify and Disconnect controls.
Draft keys stay only in memory until explicitly saved into their existing
Keychain account. Category/window switches preserve unfinished input. Login
Items continue to show observed macOS state separately from requested intent.

## Tags and tasks

Todo is pinned and cannot be renamed or deleted. Custom tags scroll horizontally
with visible overflow controls; Add and All tags remain reachable. The selected
tag exposes an ellipsis menu, with context menus and keyboard reorder retained.
All tags opens a searchable manager with full names and task counts. The same
manager appears in Settings. There is no artificial tag-count limit.

The task heading reports counts for work to do and confirmed completions. A
disclosure opens completed rows. Queued Obsidian changes stay visible above it.

Delete-list confirmation names the list and number of tasks being removed.
Affected unsaved drafts block deletion and offer Return to draft; they cannot
be silently hidden or overwritten. One Undo restores the complete list and its
tasks. Task and list deletions share a 20-operation session Undo history, shown
on Home and in tag management, including Settings.
Per-list drafts and matching asynchronous save identity remain unchanged. See
[built-in tasks](builtin-tasks.md) for data guarantees.

## Pointer and app lifecycle

Native transient outside-click dismissal and status-item toggling remain.
Pointer departure waits 180 ms after the 300 ms opening/presentation guard.
Current button, content and window/arrow geometry is reconciled every 50 ms only
while shown. Closing cancels pending work, ignores stale events and resets quick
navigation only after the native closing animation finishes.

Editing, native menus and complete native tag-drag sessions hold the panel
independently. Leaving a drop target hides its marker without releasing the drag
hold. Successful drop, outside release and Escape all end the native session;
when the final hold ends, pointer geometry is reread and normal dismissal resumes.

Automatic update installation requires both surfaces closed, no unfinished
session drafts and no pending local writes. Explicit restart and quit check
before launching the installer. Closing Settings retains drafts without prompting.
See [auto-update](auto-update.md) for the unchanged verification chain.

## Verification

Unit/render tests cover navigation targets, singleton settings, dirty-input and
installer protection, task/tag storage, overlapping interaction holds, provider
state truthfulness and measured layout in light/dark appearances. English and
Simplified Chinese are inspected at actual product dimensions. Actual mouse,
keyboard, Chinese IME and animated transitions require runtime acceptance in
addition to test results; see [motion](popover-motion.md).
