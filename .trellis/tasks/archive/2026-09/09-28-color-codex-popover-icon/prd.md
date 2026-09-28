# Color Codex icon in popover

## Goal

Show the supplied blue and violet Codex artwork next to the real usage value in Pulse's popover. Keep the status readable in light and dark appearance.

## Confirmed facts

- The highlighted Home status icon currently renders the bundled monochrome `CodexMenuIcon.png` as a template with secondary foreground color.
- Usage detail uses the same monochrome template artwork. The macOS menu bar deliberately uses that template image for system tinting.
- The supplied `codex.png` is byte-identical to the reference project's color artwork. It is an RGB PNG with an opaque white background.

## Requirements

- Use the supplied Codex colors for the icon in the Home status summary and Usage detail.
- Preserve the existing usage value, status formatting, navigation, and data retrieval.
- Keep the menu bar icon as its existing monochrome template.
- Ensure the color artwork has a transparent background so it looks correct in both light and dark appearance.
- Keep the existing reference-project attribution current.

## Acceptance Criteria

- [x] Home shows the blue and violet Codex icon beside its real percentage or short status.
- [x] Usage detail shows the same color icon.
- [x] No visible white square surrounds the icon in light or dark appearance.
- [x] The menu bar icon and usage behavior remain unchanged.
- [x] The app builds and existing tests pass.

## Out of scope

- Other Provider icons, provider data, Obsidian, menu bar styling, and layout changes.

## Open questions

- None. The screenshot, supplied artwork, and local code establish the intended result.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
