# Obsidian Today Tasks sync

## Scope and ownership

The desktop Personal Dashboard plugin owns the Today Tasks projection and its
writeback to Markdown. Pulse displays that projection through an opt-in Today
Tasks tab, with separate native Todo, tag lists and persistence. Day boundaries
follow the Mac's local calendar date. Pending adds take the day of their first
writeback. Targeted changes require the task to still be in that day's plan.

## Local protocol

The channel is `Application Support/Pulse/ObsidianToday/v1/<vaultID>` under the
current user's Library. The vault ID is the lowercase SHA-256 of the
NFC-normalized POSIX real path, encoded in UTF-8. Use private directories and
reject symbolic links in the channel. Never put live vault paths or task
content in logs, repository fixtures or release assets.

Pulse alone atomically replaces `client.json`. It contains `version: 1`,
`vaultID`, `enabled`, and `operations`. `cache` and `failures` are optional
Pulse-local state. Each operation has a lowercase UUID `id` and one of:

| Kind | Operation fields |
| --- | --- |
| `add` | `title` |
| `complete` | `taskID`, `day`, `expectedTitle`, `expectedCompleted`, `completed` |
| `delete` | `taskID`, `day`, `expectedTitle`, `expectedCompleted` |

The plugin alone atomically replaces `board.json`. It contains `version: 1`,
`vaultID`, `heartbeat` in epoch milliseconds, and `receipts` with `id` and
`code`. When the plugin has a usable snapshot it also includes both `day`
(Gregorian YYYY-MM-DD) and `tasks`. Tasks carry an opaque SHA-256 `id`
derived from the dashboard task key, `title`, `completed`, and `source`
(`quick` or `project`). Allowed issue codes are `sourceUnavailable`,
`protocolMismatch` and `storageUnavailable`. Receipts use `applied`,
`conflict`, `expired`, `unsafeDelete` or `invalid`.

## Consistency checks

- Revalidate task identity, date, title and completion against the current
  dashboard transaction. Delete only a safe standalone quick-capture row.
  Removing a project task from Today updates its plan instead of its note.
- Keep queued edits until an acknowledgment. Hold an applied overlay while
  a fresh snapshot is unavailable. Preserve failed actions with a separate
  explanation. An explicit conflict retry uses a new operation ID and a
  recently read row that still matches the original identity and title.
- Do not collapse same-title tasks. Durable operation IDs allow replay after
  interruption and distinguish identical captures. Offline queues are scoped
  to one vault and can resume on reconnect.
- Validate malformed or incompatible files without replacing their bytes.
  Preserve the last readable current-day snapshot when connection or source
  reading fails. Expire the presence indicator after the heartbeat becomes
  stale. A previous-day snapshot must not masquerade as today's list.
- Keep all I/O out of SwiftUI. `TodayBridgeStorage` owns the sequential file
  operations. The app delegate owns the shared bridge and retains per-vault
  drafts across Home, Settings and dismissal. Unsaved drafts and short local
  writes participate in the app's exit/update policy. Durable queued writes
  don't prevent relaunch.

## Verification

Use a temporary vault and a separate channel for tests. Exercise both
directions with Swift and Obsidian, rollback and replay scenarios, identical
titles, unrelated note-byte preservation, missing sources, stale checkbox
changes, and project plan removal. Keep the actual vault for read-only
post-install verification.
