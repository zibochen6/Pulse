# Apex checkbox write-back contract

## 1. Scope / Trigger

Completion/uncompletion of ordinary checkboxes and creation in an existing group
in the verified Apex file. Views do not read or write Markdown. No reordering, parent cascade,
plugin dates, Vault scanning, database or watcher.

Creation receives a typed `DashboardTaskCreationRequest` with original snapshot,
unique request UUID and `DashboardTaskDestination(column:card:)`. Insert a new
unchecked task line followed by the exact adjacent comment
`<!-- pulse-task-id: pulse-UUID -->`. Keep this Pulse creation marker outside
the checkbox text and separate from a task's actual Obsidian `^block-id`; it
permits strict idempotent retries after an uncertain save without changing the
label that Apex displays.
Resolve the original destination in latest bytes, allowing only a uniquely
validated group after external changes. Preserve every existing byte via a splice,
then coordinated atomic replacement with revision check and post-save parse.
Parent-directory permission is required for the sibling temporary file; fail
instead of truncating the original. Preserve POSIX mode/owner, ACL and xattrs.
Creation and checkbox operations use the same serial worker; keep the existing
strict external-edit locator rules. Source generations reject old UI responses.
Old checkbox requests across the app's own verified insertions may translate
byte offsets only through an exact same-file insertion proof. Bound this history
to 16 revisions/8 MiB; eviction or any unrelated external edit returns to strict
relocation/conflict rules. It is not a cache of arbitrary external revisions.
See [creation design and limits](../../../docs/apex-task-creation.md).

## 2. Signatures

```swift
protocol DashboardFileStoring: Sendable {
  func load(fileURL: URL) async throws -> Dashboard
  func setCompleted(_ completed: Bool, task: DashboardTask,
                    snapshot: Dashboard, fileURL: URL) async throws -> Dashboard
}
// @MainActor controller; nil means rejected/duplicate intent.
func setCompleted(_ completed: Bool, task: DashboardTask) -> Task<Void, Never>?
```

## 3. Contracts

- Task source retains raw line, one-based line, byte offset, checkbox marker,
  column/card anchors, ancestors and neighbors. File URL and genuine Obsidian
  block ID remain available; `pulseCreationIdentifier` is separate metadata.
- The writer places the exact Pulse creation comment immediately after a
  checkbox row. Only a valid, immediately adjacent, unique identifier is attached
  in the model. Detached, malformed or duplicate comments are optional metadata:
  they must not blank the Dashboard or hide legitimate checkbox rows. Never
  guess ownership across blank lines. Creation retries inspect raw request-ID
  occurrences and refuse uncertain associations rather than insert duplicates.
  Pulse retry IDs alone cannot authorize stale checkbox relocation; retain the
  ordinary raw-line, structure and neighbor checks. Do not add the Pulse ID to
  task text or treat it as a block ID.
- An uncertain creation retry needs proof of the exact insertion into its
  original snapshot: either the complete document, or a uniquely anchored
  destination card, must match byte-for-byte after ordinary checkbox state
  normalization. Include whitespace, native block IDs, notes and fences. A
  surviving marker/text pair cannot prove ownership after external rewriting.
  Fresh proposed/persisted creation validation instead uses the current trusted
  `Patch.data`; do not compare it against an older snapshot or reject legitimate
  intervening edits and serialized app insertions.
- UUID presentation identity is independent of completion/line changes; only
  unambiguous one-to-one source matches preserve it. Duplicate IDs are not keys.
- Snapshot bytes stay in memory. No private content, paths or locators in logs.
- The shared background serial queue owns coordinated read/patch/verification.
  Do not rely on actor isolation across awaits to serialize a file transaction.
- Reread the latest file; compare the whole document with ordinary state bytes
  normalized, or relocate via unique validated anchors/context. Never guess.
- Patch one ASCII byte with `pwrite`, flush, then reread and parse. No truncation,
  regenerated Markdown or stale full-file rollback. Preserve BOM/newlines.
- Explicit desired state is idempotent. A special marker never becomes ordinary.
- Ordinary bookmarks remain appropriate for the non-sandboxed app; balance any
  available scoped access, and handle actual permission errors. Sandbox migration
  needs its own read/write entitlement and file-only access validation.
- Selection generations and actual monotonic file observations reject stale
  replies. Refresh must not unmount a loaded list; errors must not fake success.
- Coordination/advisory locks cannot guarantee exclusion of uncooperative editors.

## 4. Validation & Error Matrix

| Input / condition | Result |
| --- | --- |
| `[ ]`, `[x]`, `[X]` | Change only state byte to explicit target. |
| Special marker | `unsupportedState`, no write. |
| Whole document differs but unique raw/structural/block anchors match | Relocate, validate current revision. |
| Repeated candidates, changed text, removed target | `conflict`, reload and explain. |
| Target already matches intent | Success without write. |
| Read-only, ACL denied, missing file, invalid bookmark | Error/reselection; no fake completion. |
| Write/flush/verification failure | Reload actual file; retain error and explicit retry intent. |
| Concurrent app saves | Shared serial queue retains every successful byte patch. |
| Repeated click while pending | Controller returns nil. |

## 5. Good / Base / Bad Cases

Good: one selected duplicate changes; all other bytes remain identical.
Base: a stale completed request meets `[X]` on disk and succeeds without writing.
Bad: adjacent edits make a duplicate ambiguous; saving stops and refreshes.

## 6. Tests Required

Assert exact-byte LF/CRLF/BOM/final-newline round trips, nested Unicode tasks,
metadata and special-state protection; duplicate text/block/card IDs; external
insertion/deletion/changed task conflicts; idempotence; concurrent same-file saves;
read-only/missing files; failed writes and post-write verification. Controller
checks pending deduplication, explicit retries, recovery, selection changes and
observation ordering. Keep parser, preferences, provider and hover regressions.
Accessibility action tests skip explicitly when the unit host exposes no buttons;
rendering never substitutes for actual desktop clicks, focus or pointer timing.

## 7. Wrong vs Correct

```swift
// Wrong: replace matching text or blindly toggle whatever is now at the old line.
// contents.replacingOccurrences(of: task.text, with: checkedText)
// Correct: explicit intent + original snapshot + uniquely validated source.
let verified = try await store.setCompleted(true, task: task,
                                           snapshot: snapshot, fileURL: url)
// Publish the verified snapshot, or reload reality on failure.
```

## Note-card bracket regression

A `- [` prefix alone does not identify a task. Notes may use `- [[Example]]`
or `- [label](url)`. `isUnsupportedCheckbox` excludes these note forms, while
actual malformed checkbox syntax still produces a parse error. A normal note
link must never blank an otherwise valid Dashboard or become writable. Include
non-checkbox note list items in parser/write-back fixtures, not just empty cards.
