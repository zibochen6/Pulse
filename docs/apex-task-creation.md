# Dashboard task creation and Settings feedback

## User flow

Both task sources have **Add task** directly below the current list. In Obsidian
mode it expands a compact footer composer in the existing 360×510 popover; it
does not replace the list with a creation page. Enter a single task line, select
a Dashboard column and existing group, then save. The selected Dashboard is the source of truth;
Pulse does not create a second copy in built-in task storage. After confirmed
save, return to the selected column. The group gains an ordinary unchecked task.
Checkbox completion and text-click opening in Obsidian remain available. The
footer also offers native multi-select hashtag suggestions and a small new-tag
field. Selected tags are appended only to the new task as ordinary `#tag` text;
case-insensitive duplicates and tags already typed in the task are not appended
again. Tags may contain Unicode, Emoji and nested `/` names, not blank spaces or
only numbers ([Obsidian tags](https://obsidian.md/help/tags)). Suggestions recognize
whitespace-delimited plain hashtags in the current Dashboard; they do not scan a
Vault or parse arbitrary Markdown. Built-in tags stay in their own JSON model.

The draft owner survives page navigation/popover dismissal during the app
session. Hover departure is suspended while the editor is visible, using the
existing editing callback. Explicit dismissal remains available. Saving disables
repeat submission, shows progress, and retains input on error. Switching to a
Dashboard explicitly clears the old snapshot's draft, even when the same file is
reselected or the new selection fails to read/parse. An observable selection
generation is reconciled above navigation; a normal refresh retains the draft.
A column without a card shows
guidance to choose another column or create a group in Obsidian; Pulse does not
invent an Apex card.

## File safety

`DashboardTaskCreationRequest` separates creation intent from views. It captures
the original snapshot, chosen column/card and stable UUID. The service rereads
the latest UTF-8 document under the existing serial file worker and file
coordination. In an unchanged structural snapshot, original group order is safe;
after external edits, only a unique validated group may be used. Ambiguous,
renamed or removed groups produce an error instead of a guessed write.

The insertion planner scans verified Apex headings, ignoring fenced examples,
and inserts one unchecked line at the end of the chosen group before its blank
separator. Original bytes remain unchanged: frontmatter, other tasks, metadata,
indentation, BOM, nearby LF/CRLF style and the presence/absence of a final newline.
Existing tasks and groups are not reordered or rewritten. Each new task receives
a separate `<!-- pulse-task-id: pulse-UUID -->` HTML-comment marker on the line
immediately after its checkbox. Apex reads the clean checkbox line as task text;
Obsidian hides the comment in rendered Markdown. Pulse keeps this marker
separate from genuine Obsidian `^block-id` anchors and associates it with the
preceding checkbox when no content intervenes.
A retry accepts the unique marked task only when its content and destination
match and the association can be verified. Raw occurrences of the same request
ID prevent a retry from inserting a duplicate when the marker has been detached,
damaged or copied. Retry ownership requires the exact original insertion to
survive: either the whole normalized document matches, or the destination card
has unique anchors and its complete normalized bytes match. Ordinary checkbox
states may change; task text, whitespace, native block IDs, notes and fenced
content must remain intact. Changes outside that card can be retained. Rewriting
inside it makes an uncertain retry fail safely, even when a leftover marker
looks attached to the right text. An auxiliary comment alone does not authorize
a stale checkbox write to a different row.

Fresh creation uses a separate exact-patch validation against the latest
coordinated file snapshot. It allows legitimate edits before the initial save
and multiple queued creations; it does not incorrectly apply the old-snapshot
retry proof to a newly generated patch.

Pulse reads checkbox tasks even if Apex or a Markdown formatter separates,
damages or leaves behind a retry comment. Only an exact, immediately adjacent,
unique comment is attached to a task; separated or duplicate markers are ignored
for display. This keeps the Dashboard usable without guessing which task owns
an orphan comment. Genuine structure errors still have explicit parse errors.
The original file is not cleaned up or rewritten during reading.

Tasks created by earlier Pulse versions may still have a visible `^pulse-UUID`
suffix because the old marker was written on the checkbox line. Pulse continues
to read those rows, but this change does not rewrite existing Dashboard content.
Remove those old suffixes in Obsidian manually or use a separately reviewed
migration; new tasks use the sidecar comment format.

Checkbox intents queued around the app's own verified insertions can translate
their original byte offsets through a bounded exact-proof history (16 revisions,
8 MiB). This does not authorize approximate external edits. Reselection rejects
undispatched intents and old UI replies, but an already accepted original-file
transaction may finish; it cannot write into the newly selected Dashboard.

Unlike one-byte completion writes, adding bytes requires an atomic replacement.
A sibling temporary file is written/flushed with the original permissions,
owner, ACL and extended attributes; revalidate the original immediately before
replacement, then reread and parse the result. An unwritable parent directory
produces a permission error. This build remains non-sandboxed with ordinary
bookmarks; no broad system permission or new dependency is introduced.
File coordination and advisory locks cannot fully exclude editors that ignore
them. There remains a small validation-to-replacement race; Pulse does not
claim absolute protection against arbitrary concurrent external writes.

## Settings controls

Settings actions now have compact visible boundaries. Save is primary; normal
actions use a subtle native background/border; removal uses red emphasis.
Hover and pressed states change fill within 80–100 ms without resizing or moving
the page. Disabled controls remain visibly disabled. Reduce Motion suppresses
these transitions. Login/name preferences use native switches and Task source
uses a segmented choice, keeping its existing independent-source semantics.
The quota fetching, task typography and popover timing remain unchanged.

## Reconnecting a Dashboard

The existing picker handoff could wait indefinitely for a single close callback.
Explicit file selection now requests close from AppKit directly. Normally the
completed close callback opens one retained `NSOpenPanel`, deferred outside the
callback. While waiting, actual popover and animated-window visibility are checked
every 50 ms; a missing callback advances only after both disappear. A two-second
unsuccessful close releases the busy state with an inline retry explanation.
Restoring an already-visible popover changes its Settings page without beginning
another Opening cycle. Cancel leaves the existing bookmark/source unchanged.
These are verified lifecycle gaps, not a claimed live reproduction of the user's
specific desktop event sequence.

## Manual acceptance with a temporary Dashboard

1. Copy `Tests/Fixtures/sample-apex-dashboard.md` into a writable temporary folder.
   Keep the personal Dashboard and configuration out of automated validation.
2. In Settings select Obsidian Dashboard and choose the temporary file. Click
   Add task in the footer, enter fictional Chinese/Emoji text and select a
   column/group and tags. Confirm the task list remains visible while typing.
3. Save. Confirm the task appears in that column and the temporary Markdown
   contains one new unchecked line. Refresh/reopen and confirm it remains.
4. Open that file in Obsidian and check the same line. Completion/uncompletion
   from Pulse should update its checkbox as before.
5. Retry a failed save with the same draft; confirm it never produces two rows.
   Test a read-only copy and an empty column for clear inline guidance.
6. Inspect Settings in light/dark appearance: actions should look clickable,
   pressing should change their fill, disabled Save key should not fire until
   text is entered, and source switching should keep both data sets independent.

## Verification

- Creation/writeback/parser/controller/editor directed suite: 66 passed.
- Reconnect/editor/settings/hover directed suite after the follow-up: 51 passed.
- Complete regression: 155 tests, 153 passed, 2 existing task-row accessibility
  tests skipped because the off-window host exposes no action buttons; 0 failed.
- Aqua/Dark Aqua editor/list/empty-column and Settings renders inspected. Full
  Settings controls were also rendered at the real 360 pt width and a taller
  evidence height because off-window `ScrollViewReader` does not reliably run
  its on-appear scroll. The actual popover remains 360×510.
- Strict Swift format lint and diff checks run before delivery. The first
  creation-test compile exposed an async-let capture of XCTest `self`; resolved
  by constructing the request before launching concurrency. Picker visibility
  test state uses a main-actor fake instead of a mutable sendable capture.
- Computer Use reads timed out. Live file-panel focus, click/save, keyboard
  operation and hover animation are not certified by rendering/unit tests.

All automated writes used fixtures/temporary documents and isolated defaults.
No personal Dashboard, API credential or real task-source configuration was
changed for validation. Local changes remain uncommitted/unpushed.

## Inline-add correction verified on 2026-10-02

- Creation now expands only the footer; existing tabs, card groups and task rows
  remain mounted. Existing local task edit/delete stays separate.
- Apex supports existing column/group selection plus ordinary hashtag choices;
  local mode keeps multi-tag JSON storage. Failed/pending saves retain stable
  intent IDs. Empty task text cannot become a tag-only task through Return.
- Directed suite: 79 passed, 0 failed. Complete suite: 162 collected, 160 passed,
  2 existing off-window AX action tests skipped, 0 failed. Build succeeded.
- Strict formatting of 29 changed Swift files and diff whitespace check passed.
- Inspected synthetic Aqua/Dark Aqua list-with-composer renders at 360x455
  (task area within the unchanged 360x510 popover), long text and empty column.
- Review caught/fixed two creation edges: Return bypassing the blank-text Add
  predicate, and an existing local task text click replacing the active draft.
  Checkbox/filter actions remain available while creating.
- No parser/provider/writer change in this UI iteration; all writes verified
  against temporary fixtures. Desktop interaction remains a separate check.

The verified PulseInlineTasks build was started after stopping the exact older
PulseApexCreation process; executable path confirmed. Computer Use returned
timeoutReached on the new build, so native menu clicks, keyboard focus and live
scroll/hover interaction remain unverified. Automated checks did not alter the
user's source preference, Dashboard bookmark or personal tasks. No commit/push.

## Detached retry-marker recovery verified on 2026-10-08

An auxiliary Pulse comment separated from its task by an empty line previously
threw a parse error and hid every task. Task deletion or formatter changes could
reproduce the same failure. Retry metadata is now optional for reading, while
mutation still requires proven ownership. The reader does not attach separated
comments to a guessed preceding task, or trust duplicated identifiers.

The writer checks raw request-ID occurrences before retrying; damaged or detached
markers cannot cause a second insertion. When the original group already has an
identical task, retry requires proof of the exact additional insertion. Checkbox
relocation no longer uses a Pulse comment as a stable task anchor.

- Directed parser/creation/writeback suite: 47 passed, 0 failed.
- Full regression: 178 collected, 176 passed, 2 existing off-window accessibility
  checks skipped, 0 failed. Strict Swift format and diff checks passed.
- A temporary harness compiled the current production sources and copied only
  the selected bookmark into isolated defaults. The production file store,
  controller and task view loaded and rendered the selected Dashboard in Aqua
  and Dark Aqua. Source-file digest and real bookmark bytes remained unchanged.
  This is full read-path/offscreen evidence, not actual popup visual acceptance.
- A signed universal Release build was installed locally as version 0.1.0,
  build 2, replacing the older installed build after a recoverable backup.
  Installed executable bytes match the repaired build; only one installed Pulse
  process remains. The previous mounted installer was ejected.
- Computer Use still timed out when reading the installed app. Live popup
  confirmation was subsequently supplied by a user screenshot showing the
  restored column tabs and checkbox task list. Read-only inspection also found
  the installed process in loaded state, with Apex selected on Home. No release,
  commit or push was performed for this fix.

All automated mutation regressions used temporary files; the personal Dashboard
was read only. No cleanup of auxiliary comments or task text was applied.
