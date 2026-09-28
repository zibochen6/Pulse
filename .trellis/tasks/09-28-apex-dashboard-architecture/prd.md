# Apex Dashboard integration architecture research

## Goal

Define a safe, read-only path from an Apex Dashboard Markdown file to Pulse's task-first menu bar view. Deliver architecture and onboarding guidance grounded in the local file and installed plugin, without implementing app behavior.

## Background

- The inspected local file is an Apex Dashboard 1.4.4 document. Its YAML frontmatter declares columns; `##` headings delimit columns; `###` headings delimit cards; card metadata includes `id` and `type`; ordinary checkbox lines represent tasks.
- The sample contains multiple columns and cards, including an empty column. A memo-like card belongs to a column rather than being a separate column. No task tag, date, reminder marker, or nested checkbox was observed in the sample.
- Pulse currently has a 360×510 task-first popover, a disconnected `TasksView`, a compact Codex status, and Settings. It has no Vault reader or task model.
- The plugin's installed code serializes and rewrites the whole Dashboard file after task changes. Pulse's first integration is display-only.

## Requirements

1. Produce six documents: `docs/apex-dashboard-analysis.md`, `docs/apex-parser-design.md`, `docs/apex-task-ui-design.md`, `docs/apex-onboarding-design.md`, `docs/apex-writeback-risks.md`, and `docs/apex-mvp-plan.md`.
2. Record only anonymized structure and aggregate observations. Do not commit the personal Vault path, task text, plugin settings, credentials, or Vault content.
3. Design the future read-only parser around Dashboard, Column, Card, and Task. Task source metadata includes `fileURL`, one-based `lineNumber`, and an optional `blockIdentifier`; line numbers are snapshot locations, not stable identity.
4. Define `DashboardConnectionState` with unconfigured, file missing, parse failed, and connected states. Distinguish a permission/read error in user-facing messaging rather than calling the file missing.
5. Design dynamic column switching that preserves source hierarchy, card-grouped task rows, and an Obsidian URI action that opens the source Markdown file without promising line-level navigation.
6. Define onboarding in Settings for user-selected Vault and Dashboard file. First-version refresh happens when the popover opens and when the user manually requests it; no file watcher.
7. Explain future writeback hazards, especially full-file rewrites, external edits, preserving Markdown, conflict detection, atomic replacement, and backups. No writeback is implemented.
8. Add `Tests/Fixtures/sample-apex-dashboard.md` with entirely invented content covering declared columns, cards, metadata, open/completed checkboxes, and an empty column. Do not add parser, UI, or test code.
9. Review the complete diff and commit locally as `docs: analyze apex dashboard integration design`; do not push.

## Acceptance criteria

- [x] All six documents exist, agree with each other, and distinguish observations from proposed behavior.
- [x] The parser design specifies source metadata and stable-versus-unstable identity; the UI opens only the source Markdown file in Obsidian.
- [x] The onboarding design covers the four connection states, missing/moved files, read permission failure, and retry or reselection.
- [x] The MVP documents a read-only scope and opening/manual-refresh policy, with no watcher or task mutation.
- [x] The fixture is syntactically representative yet contains no personal task text or paths; repository diff contains no private Vault data.
- [x] No app source or generated project file changes; the documentation diff passes whitespace/link/privacy review and is committed locally without a push.
