# Polish task first UI design

## Goal

Improve task list typography, density, and visual hierarchy without changing functionality.

## Requirements

- Keep the Home page task first while preserving the existing Apex, Provider,
  Obsidian-open, and popover behavior.
- Use a compact header with Pulse identity, small usage summaries, and Settings.
- Tighten task tabs, groups, rows, checkbox indicators, hover feedback, and
  completed-task presentation for a 360×510 popover.
- Keep original Apex column names and task order. Do not add write-back,
  filters, provider features, or file watching.

## Acceptance Criteria

- [x] Tasks remain the dominant Home content in the 360×510 popover.
- [x] Long, completed, empty-column, light, and dark task states render.
- [x] A task still opens its Dashboard file in Obsidian.
- [x] Existing build and unit tests pass.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
