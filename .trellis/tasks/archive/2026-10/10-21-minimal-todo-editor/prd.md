# Minimal Todo list and editor

## Goal
Make tasks the visual focus while keeping native styling and the 360 x 510 popover.
User approved task creation and the complete plan, then explicitly requested implementation.

## Requirements
- Remove the persistent top composer. Place a centered lightweight plus after all tasks and the completed group, inside scrolling content; empty lists show a short hint and plus.
- Plus expands an inline composer, focuses it, defaults to current list. Extra options are disclosed. Successful save clears and collapses; failure retains input with retry. Esc/collapse hides without discarding draft. Reopening restores it. Drafts survive list switching and popover closure.
- Keep separate tag-bar plus: independently create empty tags then select and expand composer.
- Editor header: Cancel / Edit task / Save. Explicit save; Cancel discards that edit. Spacious multiline content with subtle adaptive fill and fewer borders. Compact List and Repeat daily rows, and low-emphasis Delete below.
- New tag is a menu action that reveals its input only when needed, in create and edit flows.
- Preserve single-list assignment, move/reveal, completed grouping, repeat, deletion undo, stable intents, IME composition guards, stale response protection, and native text undo.
- Collapse only the exact successfully submitted draft; never overwrite newer input or manipulate another selected list. Hidden unfinished input alone must not indefinitely suspend pointer dismissal.

## Acceptance
Isolated tests cover expand/collapse, success/failure, changed drafts during save, switching, draft restoration, new tag, repeat and undo regressions. Verify keyboard/IME protection. Render empty, long, completed and editor/new-tag/error views in Aqua and Dark Aqua at actual size. Attempt live native QA with isolated data and report limitations truthfully.

## Out of scope
Storage/schema changes, usage/account/update UI, release publication and replacing the installed production app. No real Todo data writes during tests.
