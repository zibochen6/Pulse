# Delete complete tag lists with undo

## User-approved outcome
On 2026-11-14 the user reported that removing a horizontal tag mixed its tasks
into default Todo. After two explicit choices, they selected **delete the entire
list and its tasks, with Undo**, and approved a separate fix task. This is the
approved implementation direction; do not repeat that decision request. It
supersedes the prior detach-to-Todo contract. The ongoing request to commit,
publish and update locally also covers this follow-up fix (0.1.9/build 13).

## Acceptance
- Deleting a custom tag removes that tag and all tasks currently belonging to
  it in one verified transaction. Default Todo and every other list/task remain
  untouched. Todo itself cannot be deleted.
- Before deletion, clearly name the list and task count, explain whole-list
  deletion and available app-session Undo, and offer explicit Cancel/Delete.
  Never say tasks will move to Todo. Empty-list deletion also supports Undo.
- One Undo restores the tag identity/name/order and every deleted task's UUID,
  text, position, completion and daily-repeat data. Do not overwrite unrelated
  later edits or replace the whole document. Conflicting IDs/names fail safely
  and preserve the recovery record; an already-restored retry is idempotent.
- Task and list deletions share a bounded 20-operation LIFO session history.
  Undo is reachable on Home and tag management in both panel and Settings.
  Buttons describe whether a task or a whole list was removed.
- Preserve recovery information for post-write verification failures and reject
  duplicate pending delete/undo work. No partial list deletion/restoration.
- Block deletion for affected quick drafts or an edited task belonging to the
  list, including an edit whose destination has been changed to another list.
  Return to draft keeps all draft identities and text. Unrelated drafts survive.
- Keep schema 1, storage validation, native text undo, stable presentation,
  localization, existing providers and updater safety. Use isolated test data.
- Existing tasks already detached by the old behavior are not guessed at or
  deleted. Do not attempt to reconstruct lost list membership from task text.

## Delivery
Regression/full tests, independent review, docs/spec sync, commit and release
through the existing verified universal build/install/publish path. Preserve
pre-existing untracked .workbuddy/ and docs/images/. No schema migration or new
persistent trash system in this fix; Undo has the existing session lifetime.
