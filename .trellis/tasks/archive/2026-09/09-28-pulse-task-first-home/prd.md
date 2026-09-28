# Pulse task-first homepage redesign

## Goal

Make Pulse's menu bar popover feel like a personal task entry point. Home shows a compact, clickable Codex status beside the Pulse identity and gives the main content area to Tasks. Full usage information lives on a separate page.

## Background

The current 360×510 Home places a 128-point scrollable Usage section above Tasks. That section includes quota windows, reset and update times, refresh, and an other-provider entry. The Tasks area uses a large centered disconnected state. The user confirmed a task-first screenshot as a structural reference, but no Obsidian tasks or other providers are connected yet.

## Requirements

1. Home keeps the Pulse icon/name and Settings gear. Beside them, show a clickable `AIStatusSummary` containing only the real Codex icon and a short status. Do not show a Usage card, reset/update time, refresh control, provider list, or invented provider values on Home.
2. With one reported quota window, show only its remaining percentage. With multiple windows, automatically show all actual windows using short labels such as `5h` and `7d`; do not add a window-selection preference. Loading, unavailable, and failure use short honest states without a stale percentage.
3. Clicking the summary opens a separate Usage page. That page retains the current `UsageView` details, including windows, reset and update times, refresh, error messages, and its existing Add Provider explanation entry.
4. Tasks occupies the main Home region using a list-ready visual structure. Until Obsidian is available, show a compact “Obsidian not connected” row and a “Connect Obsidian” entry that leads only to the existing Settings explanation. Do not render fake tasks, a Memo tab, an Add Task control, or a large centered empty state.
5. In-popover navigation has only Home, Usage, and Settings page states, with no navigation stack. Back from Usage or Settings returns Home. Closing and reopening the popover starts at Home.
6. Preserve the menu bar status item's existing format, `UsageController` refresh behavior, Codex Provider/transport, AppKit popover behavior, current settings, and macOS 13 support. No new provider, Vault access, database, or business feature is part of this task.
7. Update `docs/ui-layout-refactor.md` and the README's current-state description. Commit locally as `refactor: make Pulse task-first homepage`; do not push.

## Acceptance Criteria

- [ ] On Home, the first and largest content region is Tasks; the only AI information outside it is one compact, clickable Codex status in the header.
- [ ] A single weekly window shows a lone percentage; multiple windows show short labeled values from the real snapshot. Loading and errors do not look like current quota data.
- [ ] Clicking AI status opens Usage details; Usage and Settings return Home, and reopening the popover starts at Home.
- [ ] Usage details retain the current real quota, reset, update, refresh, and explicit error content, with overflow scrollable.
- [ ] The disconnected task presentation is compact and list-ready, with no sample rows or nonfunctional task controls.
- [ ] Light and dark rendering, build, complete unit tests, strict format check, and diff check pass. Runtime desktop paths are attempted and any unobservable paths are recorded accurately.
- [ ] Codex fetching code and menu bar formatting are unchanged; the work is committed locally without a push.
