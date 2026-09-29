# Adjust task UI density and typography

## Goal

Make the fixed 360×510 Pulse popover read as a compact macOS utility rather
than a mobile task app, without changing its layout or behavior.

## Requirements

- Reduce the Home header to a 18–20 point Pulse title with a smaller identity
  icon and less vertical padding.
- Keep tabs near 32 points including their container, task rows at 36–40
  points, task text at 15–16 points, group labels at 13–14 points, and
  checkbox symbols near 16 points.
- Preserve dark mode, task hover/press feedback, scrolling, column switching,
  and opening the source file in Obsidian.
- Do not modify the Apex parser, task models, provider or Codex state, or the
  popover lifecycle.

## Acceptance Criteria

- [x] The compact Home view leaves more usable vertical space for tasks.
- [x] Typography and actual row height match the density targets.
- [x] Existing light/dark rendering and full unit test suite pass.
- [x] The code is committed as `refactor: adjust task ui density and typography` without a push.

## Notes

- This is a visual-only adjustment; no task behavior or data contract changes.
