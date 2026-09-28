# Pulse Phase 2A: Codex usage

## Goal
Replace the Phase 1 static `--%` menu bar readout with real Codex rate limits while preserving the native menu bar foundation.

## Requirements
- Read the installed Codex app-server's `account/rateLimits/read` response after its initialize handshake.
- Model usage independently of SwiftUI and Codex, allowing quota windows, balances, costs, and unavailable states in later phases. Only Codex is implemented now.
- Refresh on app launch and periodically, without blocking the main thread.
- Show loading, success, unavailable, and error states honestly in the menu bar and Usage section.
- Show one percentage for one reported window; include short window labels when multiple are reported. Preserve reset times in the popover.
- Test parsing, error cases, formatting, and refresh behavior with synthetic data and mocks. No live account in automated tests.
- Document implementation, verification, and known limits in `docs/phase2-codex-provider.md`.

## Constraints
- Keep macOS 13, Swift 6, AppKit status item, and SwiftUI popover.
- Do not add other providers, API keys, Obsidian, database, or full business UI.
- Keep account identifiers and raw app-server output out of logs, tests, and committed files.

## Acceptance
- A logged-in local Codex installation shows real remaining quota in the menu bar and details in the popover.
- Missing CLI, rejected request, malformed response, timeout, or absent quota shows a clear non-fabricated state.
- Xcode build and tests pass; relevant source and documentation agree.
- Changes are committed as `feat: integrate codex usage provider`.
