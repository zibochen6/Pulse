# Design

## Boundary

`Features/Tasks` owns file configuration, bookmark resolution, parsing,
connection state, refresh, and the read-only task UI. `PulseAppDelegate` owns
one controller and asks it to refresh when the popover opens. `HomeView` only
receives the controller; it does not read files or parse Markdown.

## Data flow

`NSOpenPanel` → `DashboardConfiguration` bookmark data in UserDefaults →
`DashboardTaskController` resolves bookmark → `ApexDashboardParser` produces
an immutable snapshot → `TasksView` renders the selected column.

The parser uses a strict, line-oriented state machine because the accepted
frontmatter is deliberately small. It requires `dashboard: true`, a `columns:`
list whose entries contain unquoted `name`, quoted or plain `color`, and plain
`type`, followed by matching `##` headings. It accepts `###` cards, optional
`id:` / `type:` metadata, and direct `- [ ]` / `- [x]` / `- [X]` task rows.
Unsupported YAML or structural ambiguity is an error rather than a fallback.

## File access

The current GitHub build has no App Sandbox entitlement. A normal Foundation
bookmark provides resilient local relocation without changing the entitlement
model. A future sandboxed release must introduce the user-selected read-only
entitlement and security-scoped bookmark creation/resolution as a separate
compatibility change.

## UI and failure behavior

Loaded data presents source-order column tabs and card groups. Rows describe
completion but never mutate the Markdown file. Missing and unreadable sources
do not retain a prior dashboard as if it were fresh. The Obsidian action uses
only `obsidian://open?path=<encoded source path>`.
