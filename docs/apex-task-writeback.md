# Apex task completion and source-file persistence

## Interaction

The existing 360×510 task-first Home layout remains in place. The left checkbox
sets a task to complete or incomplete; the text button opens its source Markdown
file in Obsidian. These are sibling buttons, with separate accessibility labels
and actions. The checkbox has a 28×30 point hit area around its 15 point symbol.
Task text remains 15 points, tabs 14 points, and group headings 13 points.

A pending indicator replaces the checkbox during a save. Only that task's toggle
is disabled; task text, other tasks, tabs, Settings and the popover remain usable.
A successful save does not move or hide the task, cascade to children/parents,
add a date, or notify the user. Completed text is muted with a light strike.
Failures appear inline with a retry or a file-reselection action. Retry preserves
the explicit requested state and original locator, rather than toggling whatever
now occupies the old row.

## Source model and format

The parser retains the verified Apex YAML columns and `##`/`###` structure,
card metadata, and ordinary `- [ ]`, `- [x]`, `- [X]` tasks. Four-space or tab
nested checkbox levels are supported under an existing parent. One-character
ASCII special checkbox markers can be displayed but cannot be changed by Pulse.
Malformed or orphaned indentation remains an error. Fenced code examples are
excluded; unterminated fences are rejected. There is no general Markdown AST,
Dataview, Tasks-plugin interpretation, due-date filter, or task reordering.

Each task retains its file URL, one-based line, block ID if present, original raw
line, byte offset of the checkbox state, column/card anchors, indentation,
ancestor lines and immediate neighboring lines. Raw snapshot bytes stay in
memory only. UUID presentation identity is separate from source location and is
reused only for proven one-to-one matches. Duplicate task text and duplicate
block/card IDs cannot silently become unique row or persistence identifiers.

`DashboardSourceDocument` scans UTF-8 bytes, treats CRLF as one newline and
supports a UTF-8 BOM. It does not normalize line endings on disk. Unsupported
encodings are rejected rather than decoded with replacement characters.

## Persistence flow

1. The main-actor controller records pending synchronously at the click boundary.
2. `DashboardFileStore` runs read, relocation, patch and verification on one shared
   serial worker queue, including operations from multiple service instances.
3. Resolve the selected file's ordinary bookmark; balance security-scoped access
   if available. Coordinate the operation with `NSFileCoordinator.forMerging`.
4. Open the existing regular file without truncation or following a final symlink,
   acquire a nonblocking advisory lock, and reread its latest bytes.
5. If the whole document matches after normalizing ordinary checkbox states, use
   the original row only after validating its complete raw source. Otherwise,
   require a globally unique block ID and unchanged task/structural anchors, or
   a unique task in an unambiguous card with matching ancestors and neighbors.
   Changed text, removed tasks and ambiguous duplicates are conflicts.
6. Recheck path/descriptor identity, file timestamps, size and content immediately
   before writing. If the latest task already has the desired state, return
   idempotent success without writing.
7. Write exactly one ASCII state byte with `pwrite`, flush with `fsync`, reread the
   source and verify its bytes and parsed completion. No Markdown regeneration,
   truncation, temporary-file replacement or parent-directory write permission
   is required. All other bytes, file mode and inode are preserved.
8. Confirm UI state from the verified read. A save/verification failure triggers
   a fresh read of reality; no stale whole-file or guessed UI rollback occurs.

The app stays non-sandboxed and continues to store an ordinary file bookmark.
Permission failures offer re-selection without Full Disk Access or entitlement
changes. A future sandboxed release must separately validate read/write
security-scoped bookmarks and access lifetime; a file-only permission must not
be assumed to grant permission to replace files in its parent directory.

## Refresh and lifecycle

Opening the popover and Settings → Tasks → Refresh reread the file. Each verified
save also returns a freshly parsed snapshot. There is no watcher or polling.
Refreshing a loaded dashboard keeps the list mounted until the new result is
available; task identities and the selected column are preserved for safely
matched tasks. File selection/removal has a generation guard. Actual worker
observations use a monotonic timestamp to prevent late replies from replacing
newer snapshots, independently of asynchronous task-start order.

The existing Opening protection, pointer reconciliation, 400 ms departure close,
status-item toggling and transient outside-click dismissal are unchanged.

## Concurrency limit

File coordination and advisory locks protect cooperating writers. They cannot
force an arbitrary Obsidian/plugin/sync process to honor the same lock. Such a
process can still change the file between the final check and the byte write,
or overwrite a successfully verified completion afterwards. Pulse checks all
observable revisions and verifies its write, but does not promise an atomic
compare-and-swap against every external editor. Avoid simultaneous editing while
saving, then refresh after external changes. Pulse never restores an old whole
file over external edits. Existing Vault backups remain useful; this feature
does not create a private backup cache or persist task contents elsewhere.

## Validation

Tests use fictional fixtures and temporary files, never a personal Vault.
Coverage includes byte-preserving LF/CRLF/BOM/no-final-newline round trips,
uppercase checkboxes, nested tasks, metadata, special states, fenced examples,
repeated text and IDs, external insertions/deletions/content changes, ambiguous
relocation, idempotent target states, concurrent saves, read-only/deleted files,
unsupported encoding, simulated save/verification failures, pending deduplication,
recovery from disk, stale responses, invalid bookmarks and retained row identity.

Build and unit-test commands are in README. Test results and desktop limitations
are reported separately; an opaque light/dark rendering does not demonstrate
mouse-event behavior. The task-row accessibility action tests explicitly skip
when the unit host exposes no accessibility buttons, rather than claiming a
successful click test. Synthetic Home renders are exported under the system
temporary directory's `PulseTaskWritebackRender` folder, not captured from the
user's live popover.

## Manual acceptance with a test file

1. Copy `Tests/Fixtures/sample-apex-writeback.md` into a disposable Obsidian Vault.
   Select that copy through Settings → Tasks. Preserve the previous Dashboard
   selection so it can be restored afterwards.
2. Click a checkbox. Confirm the row shows pending briefly, then a check; the
   task stays in place. Inspect Markdown in Obsidian Source mode: only its `[ ]`
   becomes `[x]`. Click again and confirm the reverse.
3. Click task text separately. Confirm Obsidian opens the file and completion does
   not change. Check both identical tasks and the nested task independently.
4. Toggle two different tasks quickly, then use Refresh, close/reopen the popover,
   and restart Pulse. Check that the file and displayed states agree.
5. Edit task text or insert an adjacent line in Obsidian before clicking a stale
   row. Pulse must either prove relocation or refuse with an inline conflict;
   it must not change another identical task.
6. Check long text, tabs, scrolling, light/dark appearance and keyboard activation.
   Keep the pointer on the menu icon for two seconds after opening, move into the
   panel, then leave both areas: the original delayed-close behavior must remain.
7. Restore the original selection and remove only the disposable test copy.

The current desktop tool cannot inspect Pulse (timeout). Real checkbox/body mouse
clicks, keyboard focus, scroll retention, hover timing and Obsidian's live reload
therefore still require this manual acceptance; unit persistence tests establish
the file-level behavior, not those desktop observations.

### Local verification result (2026-09-30)

- Debug build: passed with Swift 6 and the macOS 13 deployment target.
- Full suite: 76 tests collected, 74 passed, 0 failed, 2 explicitly skipped.
  This includes all 52 pre-existing regressions and 22 new persistence/controller
  tests. The two skipped cases are hosted accessibility action checks, not
  successful desktop click checks.
- Strict Swift formatting lint and `git diff --check`: passed.
- Aqua/Dark Aqua fictional-task renderings: inspected at the fixed popover size.
- Computer Use: Pulse inspection returned a timeout; live mouse/keyboard,
  scrolling/hover and Obsidian reload were not verified. Real configuration and
  real tasks were not changed for acceptance.
- Xcode's XCTest libraries warn that they were built for a newer macOS minimum
  than the application's deployment target. Tests passed on the current Mac;
  actual macOS 13 runtime behavior was not tested on a separate system.

## Regression: note links must not invalidate task parsing

A notes card may contain `- [[Example/Note]]` or
`- [Documentation](https://example.com)`. The legacy malformed-task fallback
classified every `- [` prefix as a checkbox, so one valid note link could replace
the entire task surface with a parse error. The fictional fixture previously
covered tasks and empty note groups, but not link list items.

The fallback now excludes wikilinks and inline Markdown links before reporting
malformed checkbox syntax. Such content remains untouched and is not exposed as
a writable task. Malformed genuine checkboxes still fail explicitly. A regression
test loads tasks together with both link forms, writes the selected checkbox,
and verifies every note byte remains unchanged. The updated parser was also
checked against the selected live Dashboard with a read-only probe; its contents
were unchanged. The stale running build was replaced with the verified new build.
