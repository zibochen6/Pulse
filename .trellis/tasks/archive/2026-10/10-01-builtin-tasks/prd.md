# Built-in tasks with multiple tags

## Goal
New users can manage tasks directly in Pulse; Apex remains an optional separate source.

## Approved requirements
- Default local tasks for fresh installs, preserve Apex for existing bookmark users; persistent Settings source selector.
- Local create/edit/delete/complete tasks, multiple user tags, all/untagged/tag filters. Completed tasks stay in place.
- Compact existing 360×510 UI and typography. Fixed add action, lightweight in-popover editor, confirmed deletion, inline pending/errors.
- Manage tag rename/delete in Settings, removing tags never removes tasks.
- Versioned Application Support JSON, background serial atomic writes; preserve data on corruption/failure.
- Suspend hover auto-close during editing only; explicit/outside closes remain. Retain drafts across accidental close.
- Do not change Apex parser/writeback, providers, add sync/dates/drag/export/general imports.

## Acceptance
Temporary-file persistence and controller tests, migration/source/filter tests, light/dark rendering, build and full regressions. Attempt isolated desktop validation and explicitly report unavailable paths. Existing untracked report retained; no commit/push/release.

## Follow-up: Apex task creation and visible Settings actions
The user now requires Add Task directly on the imported Obsidian surface, plus
clear Settings buttons and lightweight interaction feedback. This explicitly
extends the prior completion-only Apex boundary. Preserve the current list,
typography, quota, tabs and hover timing; do not add general Markdown imports,
dates, watchers, providers or change real user tasks during tests.

Add one ordinary unchecked task to a user-selected existing column/card, through
the coordinated serial file service. Keep existing bytes and external edits;
uniquely resolve the destination, reject ambiguity, validate/re-read after a
safe insertion, retain failed drafts and prevent duplicate submissions/retries.
No card creation is needed; empty columns without a card must explain that the
user needs a card in Obsidian. Editing suspends hover close just like local tasks.
Settings actions need visible primary/secondary/destructive buttons, subtle
hover/press feedback and accurate disabled state in light/dark appearance.

## Reconnect regression acceptance
- Reselecting Dashboard must open one visible native chooser after closure.
- A lost close callback cannot leave selection permanently busy; a still-visible
  timeout releases the wait and offers a clear retry error.
- Cancel preserves source/bookmark; reselect clears old snapshots/drafts even
  after parse/read failure, while ordinary refresh retains input.
- Preserve existing density, animation, hover timing, quotas and task source semantics.

## Inline creation correction
- Add tasks directly in the footer of the existing list; never replace the list
  with a full-page creation form. Keep tabs, groups and task rows mounted.
- Apex footer supports text, existing column/group and optional Markdown tags;
  built-in footer supports text and existing/new local tags.
- Keep compact type sizes, pending/error/draft retention and hover edit guard.
  Persistence/retry/destination safeguards stay in their existing services.
- Save/cancel from the footer; new tasks remain in their chosen destination.
