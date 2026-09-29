# Apex Dashboard Read-only MVP

## Purpose

Pulse gives a compact menu-bar view of one user-selected Apex Dashboard file.
It does not replace Apex Dashboard or Obsidian: the source Markdown remains the
only place where tasks are managed.

## Supported Apex format

The reader accepts the format verified during the local research:

1. A UTF-8 Markdown file begins with `---` frontmatter and contains
   `dashboard: true`.
2. The frontmatter declares ordered `columns`, each with a simple `name`,
   `color`, and `type` value.
3. The body has exactly one matching `## Column` heading for each declared
   column. A column may be empty.
4. `### Card` headings group direct `- [ ]`, `- [x]`, and `- [X]` task rows.
   Card `id:` and `type:` metadata are retained when present.

Pulse intentionally does not parse arbitrary YAML, Markdown AST nodes,
Dataview, Obsidian Tasks-plugin syntax, nested checkboxes, dates, reminders,
or tags. A task outside a card, an undeclared column, missing expected column,
or unsupported structure produces a visible parse error instead of silently
showing incomplete data.

## Reading and configuration

Settings → Tasks lets the user choose one `.md` Dashboard file. The current
GitHub build is not sandboxed, so Pulse stores a normal Foundation bookmark in
UserDefaults to find that choice after a relaunch. It stores neither a plain
path nor task text. A sandboxed distribution will need a separate migration to
user-selected read-only access and security-scoped bookmarks.

Pulse reads the file every time its popover opens and when the user selects
Refresh. There is no file watcher, background polling, cache of task text, or
automatic sync. If the file was moved, is unreadable, or cannot be parsed, the
task panel explains the state and offers Settings or retry rather than showing
a stale snapshot as current.

## Interface

The Home page keeps its Pulse and compact AI-status header. The task region
shows source-order column tabs, then card titles and read-only task rows. A
completed row is visually subdued. Empty columns show `No tasks`.

Clicking a row creates `obsidian://open?path=...` for the source Dashboard
file. The first release does not navigate to the row's line number or block
identifier. `sourceFileURL`, one-based `lineNumber`, and an optional explicit
Markdown block identifier remain in the task model only to support a future,
separately designed editing workflow.

## Limits

Pulse cannot check, create, edit, move, delete, search, or summarise tasks in
this MVP. It does not scan a Vault, infer "today" tasks, or modify the selected
Markdown file.
