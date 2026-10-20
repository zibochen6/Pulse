# Built-in task storage

## 1. Scope / Trigger

Pulse's only task system is local JSON at
`Application Support/Pulse/tasks.json`. Task data never lives in UserDefaults.
Default Todo is a virtual list represented by empty `tagIDs`; custom lists use
one tag UUID. No database, reminder service, sync or new dependency is introduced.
Test callers inject a temporary URL; never test against the user's real file.

## 2. Signatures

```swift
enum LocalTaskMutation: Sendable {
  case saveTask(id: UUID?, text: String, tagIDs: Set<UUID>,
                newTagNames: [String], repeatsDaily: Bool = false,
                creationID: UUID = UUID())
  case createTag(id: UUID, name: String)
  case deleteTask(UUID)
  case restoreTask(LocalTaskDeletionReceipt)
  case renameTag(id: UUID, name: String)
  case deleteTag(UUID)
  case setCompleted(taskID: UUID, completed: Bool)
  case completeRepeating(taskID: UUID, completedAt: Date)
  case resetRepeatingTasks(today: Date)
}

protocol LocalTaskStoring: Sendable {
  func load() async throws -> LocalTaskSnapshot
  func mutate(_ mutation: LocalTaskMutation) async throws -> LocalTaskSnapshot
}
```

`LocalTaskSnapshot` carries document, monotonic `observedAt`, and an optional
transaction-current deletion receipt. `LocalTaskDeletionReceipt` records the
complete task, index, neighboring task IDs and receipt identity/time. A deletion
write/verification error carries its receipt through `LocalTaskDeletionError`.
The main-actor controller owns `deletionHistory` and `undoDeletion()`.

## 3. Contracts

### Transactions and compatibility

- UUIDs identify tasks/tags. Ordinary edits and completion preserve task identity
  and stored order. New saves have at most one logical destination: zero or one
  existing tag, or one staged new tag, never both.
- Names/text are trimmed; tag names use one shared case-insensitive canonical
  comparison. Todo is reserved; it cannot be created or reached by renaming a
  custom tag. Create-tag uses a stable UUID for verification-failure retry.
- A shared serial background queue covers all instances. Reread the file,
  validate the staged document, atomically replace JSON, then reread and verify
  exact bytes before publishing. No-op transactions do not write.
- Validate original legacy JSON before compatibility work. Stored Todo tags
  merge into default Todo; multiple memberships keep the first tag in original
  tag creation order, with a selected legacy Todo resolving to default. Preserve
  task ID, text, completion, repeat data and order. New writes enforce <=1 ID.
- Before normalization changes source bytes, save and verify the exact original
  bytes at the compatibility backup path. Never overwrite a different existing
  backup. A failed backup leaves the source unchanged. Repeated normalized loads
  neither rewrite nor replace the backup.
- Keep schema **1**, existing `tagIDs` arrays and optional repeat keys. Stable
  key/UUID ordering and UTC ISO8601 whole-second days support byte verification.
  Corrupt/unsupported documents reject mutations and remain on disk; a missing
  initial file is a valid empty document, not a reason to eagerly create it.
- Snapshot observation time rejects older replies. Stable creation IDs support
  retry after committed-but-unverified writes; never deduplicate by task text.

### Delete and restore

- Capture deletion receipt from the transaction's latest reread, not the view.
  Successful deletion returns it; ambiguous write failure retains it while the
  controller reloads actual state. Do not register a deletion that did not occur
  or register two receipts for one successful retry.
- Keep a bounded, ordered 20-receipt LIFO history for the app session, without a
  timer. Tabs, Settings and popover closure do not clear it. Pending duplicate
  delete/restore operations are guarded. Failed restore retains its receipt.
- Restore rereads latest state and inserts only the deleted task. Use surviving
  neighbors, falling back to the original bounded index. Remove references to
  deleted tags so the restored task lands in Todo. An already-identical task is
  a successful no-op retry; a conflicting UUID is an error, never an overwrite.
- Tag deletion detaches classification only; tasks become default Todo. It never
  deletes tasks or recreates removed tags during undo.

### Daily repeat and error ownership

- `.completeRepeating` captures local-calendar completion day from the click
  instant, is idempotent within a day, and rejects non-repeating targets with
  `taskNotRepeating`. Un-completing clears the day; disabling repeat clears it.
- Reset reopens only repeating tasks completed before today or with unknown
  day. It runs on popover open/surface appearance; missing loaded state is a
  no-op. No changes means no write. It never raises user-save `isSaving` or
  clears a visible error; failed reset still reports confirmed state/error.
- Completion failures are per-task desired-state intents with original click
  instant. Another task's success cannot erase/redirect them. Retry repeating
  completion with that original instant even after midnight.
- Failure after replacement reloads actual storage; never roll back unrelated
  work from an old whole-document snapshot. Inputs survive failed saves.

## 4. Validation & Error Matrix

| Condition | Required outcome |
| --- | --- |
| Missing file | Empty in-memory document, no file creation on ordinary load. |
| Empty title/name, duplicate name, multiple destinations | Reject without partial tag/task creation. |
| Reserved Todo name | Select default in UI; storage rejects custom creation/rename. |
| Invalid UUID references, corrupt/newer JSON | Reject; keep original bytes. |
| Legacy Todo/multiple membership | Verify original backup, normalize deterministically. |
| Backup cannot be written/verified or differs | Fail closed; do not replace source. |
| Write succeeds but verification fails | Publish only reloaded confirmed state; retain stable retry/undo intent. |
| Restore target tag disappeared | Restore task to default Todo. |
| Restore UUID has different current contents | Conflict; retain undo receipt, preserve current task. |
| Old asynchronous reply arrives late | Do not replace newer observed document. |

## 5. Good / Base / Bad Cases

- Good: create an empty Work tag, add one task there, delete and restore it at
  its original relative position while another task's edit stays intact.
- Base: existing untagged tasks show in Todo alongside independent empty tags.
- Bad: normalization backup fails, or delete replacement is ambiguous. Keep
  source/recovery information, display error, and allow explicit retry.

## 6. Tests Required

Use temporary stores and injected writers. Cover independent tag lifecycle,
case/whitespace duplicates, reserved Todo, single-membership writes, exact-byte
legacy backup/idempotent conversion, backup failure, corruption/newer versions,
concurrent stores, stable creation retry, postwrite verification, stale replies
and pending deduplication. Delete tests assert transaction-current content,
relative order, bounded LIFO history, intervening edits, missing-tag fallback,
conflicting/already-restored IDs, failed writes and successful retry without
duplicate history. Draft/render tests cover frontend contracts separately.

Keep daily-repeat coverage for flag/day persistence, original click day,
same-day idempotence, stale/unknown-day reset, unchanged non-repeating/today
rows, no-op writes, non-repeating rejection, retry ownership, maintenance
`isSaving` and error preservation. Runtime mouse/IME acceptance is separate
from unit/render results.

## 7. Wrong vs Correct

```swift
// Wrong: a stale UI snapshot can overwrite unrelated edits during Undo.
try write(oldDocument)

// Correct: serialize a target-only transaction against the latest disk state.
try await store.mutate(.restoreTask(receipt))
```

Never infer transaction-current deleted contents from `controller.document`;
return the receipt from the same transaction that removes the row.
