# Implementation checklist

1. Inspect the current AppKit popover owner, Home/Usage/Tasks/Settings views, UsageMenuFormatter, README, and rendering tests. Start a new `codex/` branch from the clean current HEAD.
2. Add the simple Home/Usage/Settings page state and reset it when the popover closes. Preserve Settings destination scrolling and the current hover controller.
3. Build a compact clickable `AIStatusSummary` in the Home header using the existing real usage state and icon. Remove detailed Usage content from Home; give `UsageView` a dedicated page with Back and vertical scrolling.
4. Make Tasks the main Home content with a list-ready shape, compact disconnected row, and Connect Obsidian explanation entry. Do not add fake rows or future-feature controls.
5. Add focused tests for single/multiple/loading/error summary, navigation/reset, and light/dark page rendering. Keep existing Codex and preference tests. Run XcodeGen only if source file changes require it.
6. Update `docs/ui-layout-refactor.md`, README, and any Trellis interaction contract that became stale. Run strict swift-format lint, Debug build, all unit tests, task validation, and git diff checks. Attempt desktop UI inspection and record limitations.
7. Review the full diff and commit `refactor: make Pulse task-first homepage`. Do not push. Archive the Trellis task and record the session after the work commit.
