# Built-in tasks and optional Apex Dashboard

Pulse provides two independent task sources. New installations start with built-in
local tasks. Installations with a remembered Apex Dashboard and no explicit source
preference retain Apex on upgrade. Settings → Tasks changes the source; changing
it or disconnecting Apex never deletes local tasks or the original Markdown.
The disconnected Apex page offers Use built-in tasks without requiring a
Dashboard connection or a trip to Settings.

## Built-in workflow

The compact task area keeps the existing 360×510 popover and typography. Use Add
Task at the bottom to expand inline input while keeping the list visible. Enter
text, select multiple tags from the menu or create tag names, and Save. Existing
task editing/deletion keeps its form. A confirmed new task retains the active
filter if it matches, otherwise returns to All so the new row is visible.
The left checkbox sets completion; task text opens its editor. Completed tasks
stay at their current position, with a checkmark and subdued readable text.
Deleting a task requires confirmation. All, Untagged and named tags filter the
list without changing the stored order. A task can occur under several tag filters.
Settings supports renaming and deleting tags. Removing a tag only removes its
association from tasks, not tasks themselves.

Edits are confirmed after persistence. A failed save retains the draft and shows
an inline explanation; use Save again to retry. Editing temporarily suspends hover
departure dismissal, while native outside-click and status-item click dismissal
still work. Unsaved local task drafts survive popover dismissal during this run;
Save or Cancel ends the draft. Drafts are not persisted across an app restart.

## Local storage

Tasks and tags use UUID identities in a schema-versioned JSON document at
`~/Library/Application Support/Pulse/tasks.json`. Preferences store only the task
source, not the tasks. The background serial store rereads the latest document for
each transaction and writes the replacement atomically. State updates only after
saving. Task creation and creation of its new tags are one transaction. Startup
restores the file. Invalid/unsupported documents remain intact and cannot be
silently replaced with an empty list. Correct the file from a known backup and
retry loading; Pulse does not automatically reset corrupt task data.

No account, database, telemetry, network sync or third-party dependency is needed
for built-in tasks. These tasks are not written into Obsidian. Keep ordinary
backups of the Application Support file; cross-device synchronization, export and
arbitrary task-format imports are not included in this release.

## Apex workflow remains available

Select Obsidian Dashboard in Settings → Tasks and choose a supported Apex Markdown
file. Existing column/card presentation, task-text opening in Obsidian and safe
completion writeback remain. Apex now also supports adding tasks directly to an
existing group; see [Dashboard task creation](apex-task-creation.md). Existing
task text editing and deletion remain separate from this integration.
See [Apex writeback](apex-task-writeback.md) for supported formats and conflict
limitations. Switching sources is not importing, converting or merging data.

## Manual acceptance

With an isolated test installation/profile:
1. Start with no Dashboard bookmark and confirm built-in tasks is selected.
2. Add a fictional task with two tags. Confirm it appears under All and each tag.
3. Edit text, toggle completion twice, and confirm the row stays in place.
4. Close/reopen and restart; saved tasks/tags must remain. Close an unsaved editor
   and reopen without restarting; its input must remain available.
5. Rename a tag, then delete it after confirming. Task text/completion must remain.
6. Confirm task deletion cancellation leaves the task intact, then confirm deletion.
7. Switch to a disposable Apex file; test column browsing and checkbox writeback.
   Switch back and confirm local tasks remain intact.
8. Check keyboard buttons, long text, dark appearance, scrolling, and the original
   300 ms opening protection (and presentation completion) / 180 ms
   pointer-departure close. An open editor
   must hold hover departure; Save/Cancel restores it.

Automated verification results and any unavailable desktop paths are recorded in
the implementation delivery. Rendering or compilation alone is not a successful
mouse-interaction test.

## Verification on 2026-10-01

- Swift 6/macOS 13 Debug build passed.
- Directed storage/controller/source/render/hover suite: 35 passed, 0 failed.
- Complete suite: 104 collected, 102 passed, 0 failed, 2 skipped. The skipped
  existing Apex button accessibility checks require a host exposing SwiftUI AX
  buttons; they are not successful desktop-click checks.
- Strict formatting lint and diff whitespace checks passed.
- Fictional-task Home, task editor/list and Settings renders were inspected in
  Aqua and Dark Aqua at 360×510. Files are in the temporary
  `PulseBuiltinTaskRender` directory; these are test renders, not live screenshots.
- Computer Use timed out for both the existing app and a new isolated build. The
  isolated app used separate test preferences and a temporary task file and was
  stopped afterwards. Real mouse/keyboard actions, dismissal/draft event delivery,
  scrolling and actual app restart therefore remain manual acceptance items.
- Test data was temporary; no real Dashboard, task file or persisted source
  selection was overwritten for verification.
- XCTest emits the existing macOS 14 minimum linker warnings against the app's
  macOS 13 target. A physical macOS 13 system was not tested.

Reproduce checks with README's Xcode commands. This implementation was left
uncommitted and was not pushed or published.

## Inline creation on 2026-10-02

New tasks use a compact footer beneath the retained list, with multi-select tags
and a new-tag input. Existing row text edit is paused until Save/Cancel, avoiding
loss of the new draft; checkbox completion and filter selection remain usable.
Confirmed saves reveal the task under its matching filter or All. Stale save
results cannot close later drafts. Full regression: 160 passed, 2 off-window AX
action tests skipped, 0 failed; temporary-file persistence and light/dark renders
verified. See the creation document for this iteration's detailed limits.
