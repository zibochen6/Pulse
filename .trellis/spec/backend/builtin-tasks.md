# Built-in task storage

Built-in tasks are Pulse's only task system: plain local JSON rows with tags,
completion and an optional daily repeat, unrelated to any other model and never
written to a note file. Store tasks/tags in versioned JSON under
Application Support/Pulse/tasks.json; task data never lives in UserDefaults.
Test callers inject a temporary URL, never the user's real store.

- UUIDs identify tasks and tags. Completion/editing does not replace identities or
  reorder tasks. Tasks can hold multiple tag IDs. Tag deletion detaches IDs only.
- The shared serial background store rereads each transaction, validates a staged
  document and atomically replaces JSON; main-actor UI publishes confirmed state.
- Nonempty task/tag text and unique canonical tag names/UUIDs are validated. Invalid
  multi-tag creation must not partially save any tags or tasks.
- Corrupt/unsupported documents remain on disk and reject mutations. A failed read
  is not an empty task list. Missing initial file is a valid empty store.
- Schema stays at version 1. `repeatsDaily` and `lastCompletedDay` are optional
  JSON keys: `repeatsDaily` is always written on encode but defaults to `false`
  when absent, and `lastCompletedDay` is written only when set, so documents from
  older builds load unchanged (and vice versa) with no migration. Bumping the
  version would strand existing files behind `unsupportedVersion`.
- `lastCompletedDay` encodes as a fixed UTC ISO8601 whole-second string (day start
  in the local calendar, rounded down), and `tagIDs` encode sorted, so two equal
  documents always serialize to identical bytes for the store's byte-for-byte
  write verification.
- `.completeRepeating(taskID:completedAt:)` records the local-calendar day of
  `completedAt` and is idempotent within that day: completing again the same day
  changes nothing, while an earlier day (or no recorded day) re-arms for the new
  day. The day is captured at the click boundary, before the queued mutation runs.
- `.resetRepeatingTasks(today:)` is idempotent: it only un-checks repeating tasks
  whose recorded day is earlier than `today` (or unknown), leaves tasks completed
  today and non-repeating tasks untouched, and — because an unchanged document
  short-circuits the transaction — writes nothing when nothing is stale. It runs
  on popover open and task-surface appearance; without a loaded document it does
  not touch disk.
- A non-repeating task never completes through the repeating path: the store
  rejects `.completeRepeating` for such a task with `taskNotRepeating` rather
  than silently falling back to plain completion semantics.
- The controller routes only repeating completions through `.completeRepeating`;
  the maintenance reset must not raise `isSaving` (which would disable typing
  mid-composition) and a successful reset must not clear a visible error the user
  still has to act on; a failed reset reports its own error and publishes
  confirmed state.
- Un-completing a task clears its recorded day, and turning `repeatsDaily` off
  clears it too, so a stale day can never make a task look re-armable.
- Stable creation intent IDs allow safe retry when a write committed but verification
  failed. Never text-match an ambiguous creation or create duplicates on retry.
- Actual monotonic observations guard asynchronous snapshot replies. Completion
  failures are associated with the failed task/explicit desired state, carry the
  recorded completion instant, and another task's success must not erase or
  redirect that retry.
- No sync, database, reminders or third-party library is introduced.

Tests cover task/tag lifecycle and reload, duplicate/empty names, the internal
`.all` / `.untagged` / `.tag` filter helpers (`.untagged` backs the
empty-vocabulary guidance state; the UI renders tag tabs only, never an All or
Untagged tab), atomic failure without loss, corruption, newer version, concurrent
stores, postwrite verification and idempotent creation retry, stale replies,
pending click deduplication, and isolated preferences. Daily-repeat tests cover:
the repeat flag surviving reload; the click day being recorded; same-day
completion idempotence; reset re-arming only earlier days while a non-repeating
task stays completed; a repeated reset leaving confirmed state unchanged; reset
without a loaded document not touching disk; `.completeRepeating` on a
non-repeating task failing with `taskNotRepeating`; a repeating completion
failure retrying with its original day; another task's success keeping that
retry data; the maintenance reset not raising `isSaving` and not clearing a
visible error; and reset failure still reporting an error with confirmed state
published. Runtime mouse interaction is reported separately from unit/render
tests.
