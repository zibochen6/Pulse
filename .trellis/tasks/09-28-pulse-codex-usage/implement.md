# Implementation

1. Inspect local `codex-usage-status` source and official app-server protocol.
2. Add provider-neutral usage domain and Codex decoder/transport with explicit errors.
3. Add concurrency-safe refresh controller and connect it to status item and popover.
4. Add synthetic parser, formatter, provider error, and mock-refresh tests.
5. Update README and `docs/phase2-codex-provider.md`.
6. Regenerate Xcode project, build/test, manually inspect runtime if possible, review full diff, commit.

Rollback: source additions remain isolated under `Core/Usage` and `Features/Usage`; menu bar wiring can revert independently if integration proves unstable.
