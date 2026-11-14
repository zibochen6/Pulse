# Whole-list deletion verification

## Outcome

The user chose complete list/task deletion with one Undo. The previous store
removed only tag associations, which made the retained tasks appear in default
Todo. The new transaction removes the selected tag and its current tasks
together and captures a whole-list receipt from the same serial-queue reread.
Undo merges that receipt into current storage without replacing unrelated data.

One mixed history retains the latest 20 task/list deletion operations until the
app quits. The control appears on Home/editor and both tag managers. Confirmation
names the list/task count and its recovery lifetime. Source and destination draft
guards protect edits even while moving a task between lists. An unrelated active
editor must be resolved explicitly before returning to another retained draft.

## Final checks

- Full Debug build and test: **259 passed, 0 failed, 2 expected opt-in demo skips**.
  `/tmp/PulseListDelete-verified-tests.xcresult`.
- Chinese localization, Undo/confirmation layout and draft checks: **9 passed**.
  `/tmp/PulseListDelete-zh-tests.xcresult`.
- Strict formatting of all 10 changed Swift files, both localization resources,
  diff whitespace and task context manifests: **passed**.
- Independent end-to-end review: **passed**, no remaining confirmed blocker;
  see `review.md`.
- Native rendered Undo surfaces inspected in light/dark for Home, active editor,
  quick-panel manager and Settings manager. Chinese Home and dark Settings
  manager were checked after the localized run. No clipping, duplicate Undo
  controls or overlaps observed. Captures: `/tmp/PulseListDeletionRender`.

Regression cases cover interleaved task positions, empty lists, unrelated later
changes, name/UUID conflicts, task repeat/completion state, atomic write failures,
post-write verification failure, mixed history, duplicate pending work, stale
snapshots and newest transaction data across uncertain retries. Confirmed
deletions remain distinct operations even when the same UUID was externally
restored and deleted again.

## Boundaries

Tests use isolated temporary stores and inert external services. The real user
task file was not edited or migrated by this fix. Existing tasks detached into
Todo by the old version remain intact; their former membership was not recorded
and cannot safely be inferred from their text. Storage schema remains 1.

Rendered-view checks are not proof of native mouse/IME delivery. This patch does
not change the existing popover motion/hover behavior; delivery verification
will separately record the signed universal app, installed process and public
artifacts.
