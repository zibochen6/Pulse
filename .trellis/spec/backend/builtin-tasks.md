# Built-in task storage

Built-in tasks are separate from Dashboard models, source locators and Markdown.
Store tasks/tags in versioned JSON under Application Support/Pulse/tasks.json;
UserDefaults contains only source selection. Test callers inject a temporary URL
and isolated defaults, never the user's real store or bookmark.

- UUIDs identify tasks and tags. Completion/editing does not replace identities or
  reorder tasks. Tasks can hold multiple tag IDs. Tag deletion detaches IDs only.
- The shared serial background store rereads each transaction, validates a staged
  document and atomically replaces JSON; main-actor UI publishes confirmed state.
- Nonempty task/tag text and unique canonical tag names/UUIDs are validated. Invalid
  multi-tag creation must not partially save any tags or tasks.
- Corrupt/unsupported documents remain on disk and reject mutations. A failed read
  is not an empty task list. Missing initial file is a valid empty store.
- Stable creation intent IDs allow safe retry when a write committed but verification
  failed. Never text-match an ambiguous creation or create duplicates on retry.
- Actual monotonic observations guard asynchronous snapshot replies. Completion
  failures are associated with the failed task/explicit desired state, and another
  task's success must not erase or redirect that retry.
- No sync, database, reminders, Vault scan or third-party library is introduced.

Tests cover task/tag lifecycle and reload, duplicate/empty names, all/untagged/tag
filters, atomic failure without loss, corruption, newer version, concurrent stores,
postwrite verification and idempotent creation retry, stale replies, pending click
deduplication, isolated preferences and existing bookmark migration. Runtime mouse
interaction is reported separately from unit/render tests.
