# Pulse popover stability and task-first home

## Goal

Stop the newly observed open/close flicker when opening the menu bar popover and make Tasks the dominant Home area, with real Codex usage shown compactly above it.

## Background

- Current branch is clean at the completed Home/Settings refactor. `PulseAppDelegate` owns one transient `NSPopover`, an `NSStatusItem`, and a `PopoverHoverController` with a 400 ms delayed close.
- The user observed flicker during real desktop use after clicking the menu bar item. Unit tests covered delayed hover closure, but not the initial click-to-open sequence.
- The current Home is a vertical scroll view with intrinsic Usage and Tasks cards; its fixed 360×510 surface leaves unused space and gives Usage more visual weight.
- The user approved the final plan, approved a new Trellis task, and chose to borrow the reference screenshot's structure without showing inactive Memo/Add Task controls or fabricated data.

## Requirements

1. Opening the popover enters a short guard period of about one second. Pointer exit events are recorded but cannot trigger hover closure during it. At its end, the current pointer geometry determines whether the panel remains interactive or begins a 400 ms pending close.
2. The panel stays visible for at least two seconds when the pointer remains on the clicked status item. Entering the popover keeps it visible. Leaving both regions for 400 ms closes it; re-entry cancels that close.
3. Clicking the status item again or clicking outside still closes the popover. Internal Settings navigation and Usage refresh do not close it. Opening/closing from a single click must not oscillate.
4. Home follows a compact AI status header, a dominant Tasks region, and a fixed bottom action. Show only the real Codex value and current disconnected Obsidian state. Keep window/reset/freshness details, refresh and explicit error states accessible without clipping.
5. Keep native light/dark appearance, Settings access, macOS 13 support, App/Core/Features/UI structure, and current Codex data retrieval unchanged.
6. Update `docs/ui-layout-refactor.md` and the relevant Trellis interaction spec. Commit `fix: stabilize popover interaction and rebalance home layout` locally; do not push.

## Acceptance Criteria

- [ ] Opening protection, geometry resynchronization, pending close, cancellation, and close/reset behavior have focused tests.
- [ ] Desktop check covers pointer held on status item for two seconds, movement into the popover, 400 ms departure, re-entry, Settings navigation, outside click and second status-item click; any tool limitation is recorded honestly.
- [ ] Home visually prioritizes Tasks (roughly 50–60% of the usable surface), keeps Usage compact (roughly 30–40%), and has no large empty bottom area or fabricated tasks/provider values.
- [ ] Home and Settings render without clipping in light/dark mode and Usage loading, success, unavailable and failure states remain legible.
- [ ] Debug build, complete unit suite, strict format lint and diff checks pass; Codex provider/transport files remain unchanged.
- [ ] Requested local commit exists on a `codex/` branch and is not pushed.

## Out of Scope

- New providers, Obsidian connection or task editing, Memo/Add Task features, database, Codex app-server changes, and broad app lifecycle rewrites.
