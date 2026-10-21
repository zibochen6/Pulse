# Built-in to-dos

Pulse uses one native local task system in `Pulse/Features/Tasks/Local/`.
Tasks and tags live in `~/Library/Application Support/Pulse/tasks.json`;
there is no account, import, source selector, database or network sync.

## Independent lists and tags

- **Todo** is the permanent default list for tasks without a custom tag. It is
  not an aggregate and cannot be renamed or deleted. Custom tags keep the order
  you set and always follow **Todo**. A task belongs to one list only; changing
  its tag moves it.
- The selected tab has an accent-tinted capsule and a shape-matched keyboard
  focus affordance. Custom tabs scroll horizontally; the trailing **+** stays
  reachable. Selecting or creating a tag brings its tab into view.
- **Drag a tab to reorder it.** While dragging, the dragged tab dims and an
  accent caret marks the slot the tag will land in. The new order is written on
  drop and survives relaunch. Dropping on **Todo**, on the left half of the
  first tab, or on the tag's own current slot changes nothing. The identical
  move is available from a tab's context menu (**Move Left** / **Move Right**,
  ⌥⌘← / ⌥⌘→) and from Settings → Tasks, so reordering never depends on dragging.
- **+** opens tag-name entry. Enter creates an empty tag, selects it and focuses
  task entry. Cancel creates nothing. Names are trimmed and compared without
  case; a duplicate offers the existing tag instead of creating another.
- A tab's context menu offers **Move Left**, **Move Right**, **Rename** and
  **Remove**. Settings → Tasks offers the same operations. Removing a custom tag
  requires confirmation, moves its tasks to **Todo**, and never deletes tasks.

## Fast entry and editing

- A left-aligned **+ Add task** row follows all task rows inside the scrolling
  list. It expands inline entry in place and focuses the
  destination-labelled input. Enter saves; confirmed success clears and collapses
  back to the **+ Add task** row.
  Failure preserves input for retry. Chinese IME candidate confirmation must
  not submit, and empty/whitespace-only titles cannot be submitted.
- Esc or the collapse control hides entry without discarding the draft. Click
  **+ Add task** again to continue. New empty tags select their list and open entry.
- Creation options are disclosed on demand. The list menu offers **New tag…**;
  only choosing it reveals name entry. Both creation and editing can create and
  select one new tag, and support **Repeat daily**.
- Clicking a task opens a compact editor with Cancel / Edit task / Save in the
  header, a multiline content area, list and daily-repeat property rows, and
  Delete below them. Save confirms changes and reveals the destination if moved.
  Cancel discards that edit, not another list's quick-entry draft.
- Quick-entry drafts are owned above navigation and kept separately per list.
  Switching lists, visiting Settings or closing/reopening the popover does not
  discard them. Pending saves capture their draft identity and destination;
  late completion cannot clear a different or subsequently changed draft.
- Explicit input focus, visible unfinished input and active editing suspend
  pointer departure dismissal. A collapsed draft or idle empty input does not. Outside-click and menu-bar
  toggle dismissal retain their normal AppKit behavior.

## Completion and deletion

- A completed task stays exactly where it is: dimmed and struck through, in
  stored order, with no section to fold it into and no heading above it. It
  remains reachable for editing, un-completing and deleting like any open task.
- Completion is published only after verified storage and disables duplicate
  toggles while pending. Failures retain a task-specific retry intent.
- Deleting from a row, its context menu or the editor removes the task without
  another confirmation. Row controls reserve their width so hovering does not
  shift text; keyboard users can reach the same action.
- **Undo** restores the last deleted task, including its UUID, content,
  completion/repeat data and position. The controller retains at most 20
  deletions for the app session across tabs/pages/popover closure; there is no
  countdown. Quit clears this in-memory history. If the original tag was
  removed, restoration goes to **Todo**. Restoring a task never replaces the
  whole document or overwrites unrelated subsequent changes.
- Text input retains native Undo/Redo and Cut/Copy/Paste/Select All through the
  AppKit responder chain. Task deletion does not hijack text undo.

## Daily repeat

`repeatsDaily` and optional `lastCompletedDay` describe daily tasks. Completing
records the local calendar day of the click (captured before asynchronous
work); repeating completion is idempotent within that day. Manual reopening
clears the recorded day, as does disabling repeat.

On popover open and task-surface appearance, reset reopens repeating tasks
completed before today or with an unknown day. Today/future completions and
non-repeating tasks stay unchanged. No-op resets write nothing. Background
reset does not raise `isSaving`, disable typing or clear another visible
failure. Failed repeating completion retries with the original click day.

## Storage, compatibility and failures

Schema remains **1**. UUID identity, stored task order, optional repeat keys,
stable UTC ISO8601 whole-second day encoding and sorted UUID/key encoding are
preserved. One shared serial queue rereads the latest file for each transaction,
validates a staged result, atomically writes and verifies the bytes before
publishing. Monotonic observation timestamps reject older replies.

Legacy stored tags named **Todo** merge into the built-in default list. Legacy
multiple-tag tasks keep the earliest-created matching tag. Normalization keeps
task identity, text, order, completion and repeat state and saves the exact
original file bytes as a backup before replacement. Repeated loads must not
overwrite that backup or repeat a completed conversion. Future task writes
accept at most one custom tag; zero tags mean **Todo**.

Missing files are valid empty stores. Corrupt, unreadable or unsupported-version
files are not empty lists and cannot be silently overwritten. Failed saves
retain drafts for retry; stable intent UUIDs prevent duplicate tasks/tags when
replacement succeeded but verification failed. Delete/restore retry must
likewise retain the recovery information and confirm actual disk state.

Tests use injected temporary files. The XCTest host disables live integrations
and uses isolated preferences plus a temporary store. Runtime mouse and input
method acceptance is recorded separately from unit and rendered-view checks.

## Manual acceptance

Use a disposable, isolated store; never make the real user's file read-only or
change the machine clock to test failures/repeat.

1. Verify **Todo** remains visible with custom tags. Seed untagged tasks and a
   legacy stored Todo tag; confirm every task appears in its single list after
   conversion and the original byte backup exists.
2. Create an empty tag using **+**, cancel another, retry a duplicate with
   different capitalization and create enough tags to require scrolling.
3. Expand **+ Add task**, add with Enter and verify success collapses entry. Reopen and
   check destination, focus, whitespace rejection, long text and Chinese IME
   candidate confirmation without submission. Collapse a draft with Esc and
   verify it remains on reopening without blocking pointer dismissal.
4. Expand options, create a new tag while adding/editing a task and move a task
   to another list. The task appears only at its destination.
5. Leave drafts in two lists, switch tabs, visit Settings, close/reopen and verify
   both drafts. Submit then change tabs/input before a delayed save returns.
6. Complete every task; verify each row stays in place, dimmed and struck
   through, and that nothing above the list changes shape. Un-complete one and
   verify it returns to its original styling in the same position, then reload
   and check both states persist. Test daily reset with an injected clock in
   tests.
7. Delete via mouse, context menu and keyboard. Verify no text reflow, immediate
   feedback and multiple Undo operations. Remove the original tag, then undo a
   task deletion and verify fallback to Todo.
8. Rename/remove custom tags from both tab menus and Settings. Confirm removal
   retains tasks and the default Todo cannot be removed or duplicated.
9. Verify text Undo/Redo, clipboard editing, typing/dirty-draft hover suspension,
   idle hover dismissal, outside click and the normal 300 ms opening guard /
   180 ms departure delay.
10. Inspect empty/populated/completed/editor/options/tag/undo states at the fixed
    360 × 380 popover size in Aqua and Dark Aqua. Simulate storage failures with
    injected writers and verify retry preserves input and confirmed data.
11. Drag a tab to the far right, to the front and back again, then relaunch and
    confirm the order survived. Verify **Todo** never moves, a drop on a tab's
    own slot changes nothing, and the caret reads as a boundary rather than as a
    selected tab. Confirm **Move Left** / **Move Right** from the tab menu and
    from Settings → Tasks land the tag in the same slot as the equivalent drag.
    With Reduce Motion on, no hover, press, disclosure, row or drag feedback
    animates and every control still behaves the same.

The previous Markdown dashboard integration was removed; native tasks are the
only task system.
