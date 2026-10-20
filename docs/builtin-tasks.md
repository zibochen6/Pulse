# Built-in to-dos

Pulse has one task system: the native local list in
`Pulse/Features/Tasks/Local/` (`LocalTask`, `LocalTaskStore`,
`LocalTaskController`, `LocalTasksView`, `LocalTagSettingsView`). Nothing is
imported from or written back to a note file, and no connection, import step or
source choice exists. This document is the current contract.

## Tabs and selection

- The tab row shows only the saved tags, in creation order. There is **no
  "All" tab and no "Untagged" tab**.
- With zero tags the bar shows a single guidance tab labeled **Todo** (always
  rendered as selected, with no action) and the empty list reads **"No tasks
  yet"**. With tags, an empty tag reads **"No tasks in this tag"**.
- Selection defaults to the first-created tag whenever tags exist; it is
  presentation state owned by `LocalTaskPresentation`, kept above page
  navigation so a popover close never discards it. It never edits a stored
  task. When the selected tag is deleted, selection reconciles to the first
  remaining tag, or back to the guidance state when no tags remain.
- A selected tab is a filled rounded capsule (accent tint) with semibold text;
  an unselected tab is secondary text with a light hover fill. Selection has no
  focus box: the macOS square focus ring is suppressed
  (`Pulse/UI/PulseFocusEffect.swift`, `Pulse/UI/PulseSharedControls.swift`) and
  keyboard focus draws a soft shape-matched stroke instead of a rectangle
  around the capsule.
- A task with several tags appears under each of those tag tabs; stored order
  is never changed by tab selection.

## Quick add

- Under the list, centered, is a `+` icon button. It expands the inline
  composer **in the same footer slot**, so the list does not jump between two
  different footers.
- The composer contains: a text field ("Add a task…"), a **Tags** menu with
  saved-tag toggles and the count of chosen tags, a **New tag** field with its
  own small `+`, a **Repeat daily** checkbox, and **Add** (`⌘S`) / **Cancel**
  (Escape). The text field takes focus on appear; the list stays visible.
- Submission is guarded at the button boundary, so a double click cannot queue
  two creations. The new task and its new tags are persisted as one
  transaction.
- A confirmed task keeps the tab that already shows it; otherwise the tab moves
  to the earliest-created tag of the new task (or stays in the guidance state
  when there are no tags) so the row is visible.

## Tag-bar add

- At the right end of the tag row, a `+` menu offers **"Add task in tag"** —
  one entry per saved tag, which opens the composer with that tag already
  selected — and **"New tag…"**, which opens the composer for a task that gets
  a brand-new tag typed into the New tag field.

## Completed tasks stay visible

- Open tasks come first; completed tasks follow under a small **"Completed"**
  heading (11 pt semibold, tertiary). Completed rows are dimmed and struck
  through. Nothing is hidden, auto-removed, or collapsed, and no count or
  disclosure control exists.
- While a toggle is pending the row shows a spinner and its checkbox is
  disabled; state updates only after the store confirms the write.
- Hovering any row reveals a trash button that opens a confirmation dialog
  ("Delete …?", **Delete task** / **Keep task**, "This cannot be undone.").
  Tasks can also be deleted from the editor page through its inline
  confirmation. Deleting a task never touches its tags; deleting a tag in
  **Settings → Tasks** only removes the association.

## Daily repeat

- Each task has an optional `repeatsDaily` flag and a `lastCompletedDay`.
  The composer and the editor share one **"Repeat daily"** checkbox, and a
  repeating task shows a small circular-arrows marker next to its text.
- Completing a repeating task records the **local calendar day**
  (`Calendar.current.startOfDay`) of the click. The instant is captured at the
  click boundary — before the asynchronous mutation runs — so a slow save
  cannot shift the completion to another day. Completion goes through
  `.completeRepeating(taskID:completedAt:)`, which is idempotent within that
  day: repeating the same day changes nothing. Un-completing uses the plain
  mutation and clears the recorded day.
- A non-repeating task never completes through the repeating path; the store
  rejects that with `taskNotRepeating` (a stale UI state, not user error).
- `LocalTaskController.resetRepeatingTasks()` runs when Pulse opens — the
  popover-open path in `PulseAppDelegate` and the task-surface appearance in
  `LocalTasksView`. It re-arms (checks off → open) any repeating task whose
  recorded day is earlier than today, or whose day is unknown; a task finished
  today stays finished and non-repeating tasks are untouched. It is idempotent
  (a second run leaves the confirmed state unchanged) and the store writes
  nothing when nothing is stale.
- The reset is background maintenance, not a user save: it never raises
  `isSaving` (so typing is never disabled mid-composition) and a successful run
  never clears an error the user still has to act on. A failed reset reports
  its own error and publishes confirmed state.

## Storage and schema

- Tasks and tags use UUID identities in a schema-versioned JSON document at
  `~/Library/Application Support/Pulse/tasks.json`. The schema version stays
  **1**: `repeatsDaily` and `lastCompletedDay` are optional keys, so a file
  written by an older build loads unchanged and vice versa. There is no
  migration.
- Day values are encoded as stable UTC ISO8601 whole seconds; `repeatsDaily`
  is always written so a file states its repeat intent explicitly. Tag UUIDs
  are sorted, and the encoder sorts keys, so equal documents serialize to
  identical bytes for the store's byte-for-byte write verification.
- One background serial queue covers all instances. Every transaction rereads
  the latest document, validates the staged result, replaces the file
  atomically, then rereads and compares bytes before the controller publishes
  state. Snapshot replies are ordered by observation time, so a late reply
  cannot roll the UI back.
- A missing file is a valid empty store. Corrupt or newer-version documents
  stay on disk unchanged and reject mutations; Pulse never silently replaces
  them with an empty list. No account, database, telemetry or network sync is
  involved.

## Failure and retry

- A failed save keeps the draft and shows an inline error with **Try again**
  and **Dismiss**; Save again retries the same intent. Creation retries use the
  stable creation UUID, so a write that committed but failed verification is
  confirmed rather than duplicated.
- A failed completion is recorded per task with the desired state, the repeat
  flag and the completion instant it was asked at. Its inline failure offers
  retry/dismiss, and another task's success never clears or redirects it;
  deleting the task drops its record. `retryCompletion` replays the recorded
  instant, so a retry after midnight still records the day the user clicked.
- If verification fails after replacement, Pulse reloads the real file state
  instead of rolling back or presenting an unconfirmed in-memory result.

## Manual acceptance

With an isolated test installation:

1. **Single task system:** no source picker or connection UI exists anywhere;
   Settings → Tasks manages tags only (rename/remove), and removing a tag
   keeps its tasks.
2. **Tag-only tabs:** with zero tags the bar shows one **Todo** guidance tab
   and the list reads "No tasks yet". Create two tags; the bar shows exactly
   those two tags in creation order — no **All**, no **Untagged**. An empty
   tag reads "No tasks in this tag".
3. **Selection capsule:** the selected tab is a filled accent capsule with
   semibold text; unselected tabs are plain secondary text with a hover fill.
   Tab through the tabs: no square focus ring appears — focus is a soft
   shape-matched stroke.
4. **Quick add:** the centered `+` under the list expands the composer in
   place (text field, Tags menu, New tag field, Repeat daily, Add/Cancel) and
   the list does not jump. A confirmed task lands on a visible tab.
5. **Tag-bar add:** the `+` at the right end of the tag row offers "Add task
   in tag" per saved tag and "New tag…"; each starts the composer for that
   tag, and the new-tag path creates the tag with the task.
6. **Completed rows:** complete a task; it stays visible, dimmed and struck
   through, under the "Completed" heading after the open tasks. Close and
   reopen the app: it is still there.
7. **Delete flows:** hover a row → trash button → confirmation dialog; cancel
   first (task stays), then confirm. Delete another from the editor; both ask
   for confirmation and both leave tags intact.
8. **Daily repeat:** create a task with **Repeat daily**; complete it — it
   shows the circular-arrows marker and stays completed today. Reopen the
   popover the same day: still completed. Reopen on a later day (or change the
   machine clock/date forward and reopen): it is open again. Completing it
   again records the new day. A non-repeating task never re-arms.
9. **Storage:** quit and restart Pulse; tasks, tags and repeat flags persist.
   The file at `~/Library/Application Support/Pulse/tasks.json` still reports
   `"schemaVersion": 1`; remove the two optional keys by hand and confirm the
   file still loads with no migration prompt.
10. **Failures:** make the file read-only or its directory unwritable and
    confirm an inline error with retry, the draft retained, and typing still
    enabled while the background reset runs; restore access and retry
    successfully.
11. **Regression pass:** keyboard operation, long text, dark appearance,
    scrolling, the 300 ms opening guard plus presentation completion, the 180
    ms pointer-departure close, and hover-suspension while an editor is open.

## Removed integration

The previous Apex Dashboard integration — Markdown parsing, the file picker,
and checkbox write-back — was removed; the native list above is the only task
system, and the old bookmark preference key is no longer read. Existing user
files and bookmarks are left untouched.
