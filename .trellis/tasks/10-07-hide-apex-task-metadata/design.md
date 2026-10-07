# Design: keep Pulse retry identity out of Apex task text

## Confirmed behavior

`DashboardTaskInsertion` currently emits `- [ ] <text> ^pulse-<uuid>`. Pulse's parser removes the suffix when it builds its own task model, while the installed Apex Dashboard plugin displays the checkbox line's raw task text. Therefore the problem is the persisted line format, not text encoding or Pulse rendering.

## Format and data flow

Write each new task as two adjacent lines:

```markdown
- [ ] <task text>
<!-- pulse-task-id: pulse-<uuid> -->
```

The checkbox line remains ordinary Apex task text. Obsidian hides the HTML comment in rendered Markdown, and Apex's line-based checkbox scanner does not include it in the task label. Pulse's narrow parser recognizes only this exact comment when it immediately follows a parsed checkbox, then stores its value in a new optional `DashboardTask.pulseCreationIdentifier` field. `DashboardTask.blockIdentifier` remains reserved for actual Obsidian `^block-id` syntax.

The creation request keeps its UUID stable across save retry and exposes it as `creationIdentifier`. The insertion service finds an existing task by a unique matching Pulse marker, then validates its clean checkbox line, ordinary state, destination column/card, and exact text. Duplicate markers or mismatches remain conflicts. This preserves the current uncertain-save protection without making visible task text carry Pulse metadata.

`DashboardTaskLocator` may use a unique Pulse creation marker as a relocation anchor after external line insertions, subject to the existing source/card checks. A marker is never treated as an Obsidian block ID. The byte-splice writer inserts the second line without regenerating existing content and continues preserving newline convention, BOM, and final-newline behavior.

## Compatibility and migration

- Existing Obsidian block IDs continue to parse and render using the current behavior.
- Existing legacy `^pulse-...` tasks remain readable as before. This fix does not edit the user's Dashboard or silently migrate those rows; an explicit later migration can safely target only validated legacy identifiers.
- The comment syntax is intentionally specific to Pulse-created tasks. Arbitrary HTML comments and broader Markdown syntax are not added to the supported Apex grammar.
- No dependency or project entitlement changes are needed.

## Boundaries and rollback

Changes stay in the task model/parser, creation request/insertion/locator, focused tests, creation docs, and the Apex write-back spec. No UI or provider behavior changes. If the plugin still displays the clean checkbox line incorrectly, revert only the new sidecar marker representation and reassess against a sanitized Apex fixture before touching any real Dashboard.

The previously existing Cmd+V worktree changes and the independent untracked report are not part of this task and must remain untouched.
