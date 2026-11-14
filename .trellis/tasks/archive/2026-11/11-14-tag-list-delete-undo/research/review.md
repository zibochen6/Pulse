# Independent whole-list deletion review

Reviewed the approved PRD/design, task manifests, storage/state/UI contracts,
transaction receipts, restoration, mixed history, draft guards, both Undo
surfaces, native menu labels and English/Chinese strings.

## Findings (fixed)

- `LocalTasksView.swift`: a dirty quick draft in list A plus an unrelated active
  task editor B caused Return to draft to select A while Home still displayed B.
  The UI now explicitly offers **Continue current edit** with an explanation.
  It retains the editor, all quick drafts and the current selection. Once the
  user saves/cancels B, returning to A works normally. Added presentation and
  bilingual label regressions. No suspended-editor subsystem was introduced.

- `LocalTaskController.swift`: multiple ambiguous delete attempts for the same
  target could retain different transaction snapshots. After a later confirmed
  absence, dictionary iteration could select an older receipt and recover stale
  contents. The storage owner now retains the newest transaction only among
  uncertain attempts. Reviewer inspected the final helpers and real-storage
  task/list regressions. Confirmed
  history continues identifying operations by receipt ID: distinct deletions
  separated by an external restore must not silently lose recovery records.

The storage owner also found and corrected promotion of a failed/no-write
deletion merely because a later task edit changed the document. Confirmed
absence, unchanged originals and ambiguous state are now distinguished; reads
older than the receipt cannot discard its recovery information.

## Findings (not fixed)

No remaining confirmed defect. All fixes are local to the approved behavior;
no schema migration, new persistence, or unrelated-draft deletion was added.

## Reviewed behavior

- Deletion captures the current tag and membership on the serial storage queue,
  removes exactly those targets, and uses the existing verified atomic write.
- Whole-list restoration validates tag ID/name and every task conflict before
  inserting targets; unrelated current data is preserved. Matching retries are
  idempotent. Empty lists and mixed 20-operation history are covered.
- Original stored membership blocks deletion even after an edited task chooses
  another destination. Validation is repeated at submission. Unrelated drafts
  remain intact. No logic guesses membership of previously detached tasks.
- A shared Undo bar is present once on Home/editor and either tag manager. It
  distinguishes task/list recovery, retains native text undo, and does not
  navigate away from Settings or manager pages. Active task editors survive.
- Confirmation names the list/count and session-limited whole-list Undo. Old
  detach-to-Todo UI strings are removed in both languages.

## Verification

- Root's initial full suite: 253 passed, two opt-in skips, before the final
  review corrections (`/tmp/PulseListDelete-tests-1.xcresult`).
- All 10 changed Swift files: strict `swift-format` lint **passed**.
- English/Chinese resources: `plutil -lint` **passed**.
- `git diff --check`: **passed**.
- Final build/type-check and full suite: **passed**, 259 passing tests, zero
  failures, two expected opt-in skips (261 total). Result:
  `/tmp/PulseListDelete-verified-tests.xcresult`.
- Chinese focused run: **passed**, nine tests, zero failures. Result:
  `/tmp/PulseListDelete-zh-tests.xcresult`.
- Reviewer independently read both result summaries. Root owns build/test
  execution; reviewer did not start competing XCTest hosts.
- Root visually inspected the Chinese Home Undo control and dark Settings tag
  manager Undo control; labels fit and remain legible. Render inspection is
  distinct from native mouse/IME acceptance.

Final source review confirmed newest uncertain receipts are selected by
transaction time, older callbacks cannot replace them, and successful receipts
clear only older/equal uncertain records. Confirmed operations continue to use
their separate receipt IDs; an external restore/edit followed by another delete
keeps both records and rejects a later conflicting restore without overwriting.
