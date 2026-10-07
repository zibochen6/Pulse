# Hide Pulse task metadata from Apex view

## Goal

Tasks created by Pulse must render in the original Apex Dashboard without Pulse retry identifiers appearing as part of their visible task text. Pulse must still recognize a creation after an uncertain save so retrying cannot create a duplicate.

## Background

- Pulse currently appends `^pulse-<uuid>` to the checkbox line when creating an Apex task.
- The installed Apex Dashboard renderer reads the checkbox line's raw task text and displays that suffix; Pulse's own parser stripping it does not affect the plugin's view.
- The `^...` syntax is an Obsidian block identifier, but Apex does not hide it from its task label.
- The user requested implementation, automated verification, and a commit if checks pass. A Trellis task record was explicitly approved.
- Existing local changes for a separate Cmd+V fix and an unrelated untracked report must be preserved and excluded from this task's commit.

## Requirements

- Newly created task checkbox lines must contain only the task text and ordinary checkbox syntax; Pulse metadata must not be appended to that line.
- Persist a stable Pulse creation identifier separately from the checkbox line so an uncertain save can be retried idempotently.
- Parse the Pulse identifier only from the exact supported adjacent metadata form emitted by Pulse; do not broaden this into a general Markdown/HTML parser.
- Keep Obsidian's actual `^block-id` parsing semantics distinct from Pulse's creation identifier.
- Keep current Apex parsing, insertion conflict checks, source location, and existing task creation behavior compatible.
- Do not automatically rewrite the user's existing Dashboard or migrate previously created `^pulse-...` rows in this change.
- Do not alter unrelated local changes or push to the remote.

## Acceptance Criteria

- [x] A newly added task is written as a clean checkbox line followed by a separate hidden HTML-comment marker, and its task label contains no Pulse UUID.
- [x] Reloading and parsing the saved file returns the original task text and the same Pulse creation identifier.
- [x] Retrying the same creation intent after an uncertain save detects the unique existing task and does not add a duplicate.
- [x] Duplicate or malformed creation markers, changed content, and ambiguous destinations fail safely.
- [x] Existing genuine Obsidian block IDs continue to parse as `blockIdentifier` and are not confused with Pulse metadata.
- [x] Tests use fixtures or temporary files and prove the Apex checkbox-line text is free of Pulse identifiers; the personal Dashboard is not modified.
- [x] Relevant build and test suites pass, the diff is reviewed, and only this bug's files/task artifacts are included in the requested commit.

## Out of Scope

- Migrating/removing identifiers from tasks created before this fix.
- Changing Apex Dashboard or Obsidian plugin code.
- Changing task completion write-back, parser coverage beyond the exact Pulse marker, UI layout, providers, or file watching.
- Pushing or publishing.

## Open Questions

None. The compatibility marker format and the exclusion of automatic legacy migration are fixed in the design below.
