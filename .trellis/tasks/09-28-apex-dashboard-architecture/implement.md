# Execution checklist

1. Reconfirm the local Dashboard's structural counts and observed syntax with read-only inspection. Verify parser/writer behavior against the installed plugin bundle, without copying private data.
2. Draft the anonymized structure analysis and parser model, separating current-file facts from plugin capabilities and future design.
3. Draft task-first UI, onboarding, connection states, refresh triggers, Obsidian URI behavior, writeback risks, and the bounded read-only MVP.
4. Create one fictional Markdown fixture under `Tests/Fixtures` matching the observed Apex layout; add no executable parser or test.
5. Cross-check the six documents against the fixture and existing Pulse architecture docs. Check external links, terminology, privacy, and `git diff --check`.
6. Inspect the complete diff, ensure only docs/fixture/Trellis records changed, commit `docs: analyze apex dashboard integration design`, archive the task, and record the session. Do not push.
