# Pulse Apex Dashboard Read-only MVP

## Goal

Let Pulse show a user-selected Apex Dashboard Markdown file in its existing
360×510 menu-bar popover. Pulse is a fast, read-only view; Obsidian remains
the task-management application.

## Requirements

- Support only the observed Apex subset: YAML `columns`, `##` column headings,
  `###` card headings, and Markdown checkbox tasks within cards.
- Parse into Dashboard, Column, Card, and DashboardTask models. Every task
  retains source URL, one-based line number, text, completion state, and an
  optional explicit Markdown block identifier.
- Persist the user-selected Dashboard as bookmark data, not a path string.
  The current non-sandboxed build must stay non-sandboxed.
- Present clear states for no selection, missing file, denied/unreadable file,
  malformed supported Apex structure, and a loaded snapshot.
- Reload when the popover opens and on an explicit refresh action. Do not add
  a watcher, polling, background sync, or local task cache.
- Display columns as tabs, cards as compact groups, and tasks as non-editable
  rows. A task opens its source Markdown file through Obsidian without
  attempting line or block navigation.

## Exclusions

No task write-back, task completion, create/delete/edit controls, Dataview,
Tasks-plugin syntax, Markdown AST, AI actions, or new provider work.

## Acceptance criteria

- The sanitised fixture proves Chinese column names, multiple cards, an empty
  column, completed and incomplete tasks, source line numbers, and strict
  parsing errors.
- A selected local Dashboard remains selectable after a controller restart via
  bookmark data. Missing/unreadable/malformed sources produce the matching UI
  state instead of stale task data.
- The Home page remains task-first and works in Aqua and Dark Aqua at the
  existing popover size. Existing Codex and 88VIP behaviour remains unchanged.
- Build and full unit-test suite pass. The work is committed as
  `feat: integrate apex dashboard readonly tasks` without pushing.

## Goal

Add a read-only Apex Dashboard parser, selected-file configuration, task browsing, and tests without Markdown write-back or synchronization.

## Requirements

- TBD

## Acceptance Criteria

- [ ] TBD

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
