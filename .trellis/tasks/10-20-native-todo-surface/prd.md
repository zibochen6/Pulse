# Native to-dos only: tag tabs, quick add, completed rows, daily repeat

## Goal

Document the native-only to-do surface: tag-only tabs with a Todo guidance tab, capsule selection without a square focus ring, centered quick-add +, tag-bar + menu, visible dimmed/struck completed rows with confirmed delete, and per-task daily repeat re-armed on popover open.

## Requirements

The six user requests driving this change:

1. **Remove the Obsidian dashboard import/parse integration.** The file picker,
   Markdown parsing and checkbox write-back are gone; `Pulse/Features/Tasks/Local/`
   is the only task implementation. Settings → Tasks manages tags only, no task
   source preference remains, and the old bookmark key is no longer read.
2. **Replace the square selection focus box with a capsule fill.** A selected tab
   is an accent-tinted filled rounded capsule with semibold text; unselected tabs
   are secondary text with a light hover fill. The macOS square focus ring is
   suppressed (`Pulse/UI/PulseFocusEffect.swift`, `Pulse/UI/PulseSharedControls.swift`)
   and keyboard focus draws a shape-matched soft affordance instead.
3. **Centered `+` quick add under the list.** A `+` icon button expands the inline
   composer in place (text field, Tags menu, New tag field, "Repeat daily"
   checkbox, Add / Cancel) without the list jumping to another footer.
4. **Completed tasks stay visible.** They are dimmed and struck through under a
   small "Completed" heading after the open tasks; hovering a row reveals a trash
   button with a confirmation dialog, and the editor still deletes with
   confirmation. Nothing is hidden or auto-removed.
5. **Tag-row `+` for other tags; no "All" tab; default "Todo".** The tag bar
   shows only saved tags in creation order; with zero tags a single guidance tab
   labeled **Todo** appears (empty state "No tasks yet"; empty tag "No tasks in
   this tag"). The `+` menu at the row's right end offers "Add task in tag" (one
   entry per saved tag) and "New tag…".
6. **Per-task daily repeat.** Optional `repeatsDaily` flag plus `lastCompletedDay`
   (local calendar day, captured at click time). `resetRepeatingTasks()` re-arms
   stale repeating tasks on popover open / task-surface appearance, idempotently
   and without raising `isSaving` or clearing a visible error. Repeating tasks
   show a circular-arrows marker. Schema stays at version 1 with optional keys
   and no migration.

## Acceptance Criteria

- [ ] All prose in `README.md`, `docs/builtin-tasks.md`,
      `.trellis/spec/frontend/state-management.md` and
      `.trellis/spec/backend/builtin-tasks.md` is free of the removed integration
      and of task-source wording (a single explicit "was removed" note allowed).
- [ ] Obsolete design docs (the old `docs/apex-*` design set, the Vault research
      note, and the removed backend write-back spec) are deleted and no live doc
      links to them.
- [ ] Design, planning and spec docs either drop the removed surface/All+Untagged
      filter row or explicitly mark it as removed, while keeping still-true
      content (popover size, dismissal timing, typography, hover controller).
- [ ] `docs/builtin-tasks.md` ends with a "Manual acceptance" checklist covering
      the numbered current behaviors and a note that the previous integration
      was removed.
- [ ] No `.swift` file, `project.yml`, `Pulse.xcodeproj/**` or `Tests/**` change
      (code frozen and verified by the lead).

## Notes

- Documentation-only task; the implementation already ships these behaviors.
- `docs/builtin-tasks.md` is the single source of truth for the current contract.
- The `task.py create` command required the documented `--description` flag in
  addition to the title and `--slug`.
