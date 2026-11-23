# Native panel and Settings interaction

This document describes the native UI introduced in Pulse 0.1.8, with complete
list deletion and Undo updated in 0.1.9.

## Surfaces and navigation

The menu-bar panel has a fixed 400 × 520 content surface. A stable toolbar with
the focus timer and settings entry sits above AI status controls, a tag strip
and the scrolling task list. Settings
opens in one independent 720 × 560 native window, with General, AI services,
Lists & tags, Updates and About categories. Reopening Settings restores the
last category; contextual configuration actions open the relevant provider.
Cmd+, opens Settings, Cmd+W closes its window, and closing it never quits Pulse.

Home, provider-specific Usage and tag management share the quick panel. Selecting
a configured provider requests its own reading and opens its details; an
unconfigured service opens its connection settings. Back restores the
Home task selection and drafts. Closing the panel resets only quick navigation,
not Settings or retained draft state. Pulse remains an accessory app with no
Dock icon.

## Information and visual hierarchy

The opaque root uses adaptive neutral colors with a restrained violet accent.
Readable task text, 16-point horizontal insets, soft tag colors and clear action
hierarchy replace dense uniform gray controls. Real provider icons retain their
identity colors. The Home strip shows icons and values in one compact row.
Long amounts keep every decimal and the strip scrolls when needed.

Codex remains a quota and other providers remain native-currency balances. No
currency conversion, fabricated percentage or stale successful value is shown
as current. Unconfigured services offer Connect; saved credentials are shown as
Connected only after successful usage verification. Errors explain a recovery
action. Refresh provides an in-place busy indicator and rejects duplicate work.

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
