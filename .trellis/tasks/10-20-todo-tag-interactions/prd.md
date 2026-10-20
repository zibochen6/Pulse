# Todo and Tag interaction improvements

## Goal
Implement the user-approved plan from the current chat: independent single-tag lists, independent empty-tag creation, continuous quick entry, safe delete with undo, retained drafts and discoverable default Todo. User explicitly approved implementation on 2026-10-20.

## Requirements and acceptance
- Always show default Todo (untagged only), never All. Each task has exactly one logical list: zero or one stored tagIDs.
- Tag-bar + is fixed outside horizontal scrolling and opens inline tag-name entry. Enter creates an empty tag, selects it and focuses quick entry; cancel writes nothing. Duplicate names trim/fold case and offer selecting existing tag. Todo is reserved, built-in and cannot be renamed/deleted.
- Quick composer stays below tag bar, above scrolling task rows. Enter saves then clears/refocuses for continuous entry; IME composition confirmation must not submit. Options for changing list and daily repeat are collapsed by default. New tag is supported from both create/edit forms and selected as sole destination.
- Changing a task tag moves it and reveals destination on confirmed save.
- Row/editor deletion has no confirmation; display Undo, restoring full task and original relative position. Keep last 20 deletion receipts in controller for app session, across popover/page changes, no timeout. Restore to Todo if original tag removed. Text editing undo stays native.
- Delete-tag remains confirmed and explicitly moves its tasks to Todo. Context menus on tag tabs support rename/delete; settings has same behavior.
- Reserve row delete-button width, expose on hover/keyboard focus and context menu; no text reflow. Completed heading always includes count, starts expanded and can collapse.
- Drafts per list survive switching tabs, Settings and popover close/reopen. New intents cannot replace unsaved input. Saves capture origin/destination and creation ID before async work; cannot clear later input. Failed saves preserve retryable draft. Hover-close suspension while focused/dirty/editing, not merely because empty quick entry exists.
- Legacy stored Todo tag merges into built-in Todo, preserving tasks/IDs/content/order/completion/repeat. Before normalization write retain exact original bytes as backup. Legacy multiple tags resolve to first tag in original creation order. Current real store has 4 untagged tasks, no multi-tag tasks; never mutate it during tests.
- Keep schema v1, atomic verified writes, serial transaction reread, idempotent retries, stale-reply guards, daily repeat and corrupt/newer-format protection.
- Keep native styling, 360x510 popover, existing English UI wording. No usage/update/provider feature changes.

## Verification
Use isolated stores for lifecycle, normalization/backup, duplicate and empty names, single membership, creation/save failures and postwrite retries, deletion/undo ordering/failure/conflict and missing-tag fallback, concurrent writes, draft retention and stale submission. Render empty/populated/completed/options/editor/tag-management/undo in Aqua and Dark Aqua. Run relevant and full regression suites. Actual native mouse/keyboard/IME checks must be reported honestly and separately from unit/render evidence.
