# Execution

1. Read curated specs and approved PRD/design; the new approved contracts supersede old multi-tag/tag-only-tab/composer/delete-confirm behaviors.
2. Implement store/controller operations and focused tests for single-list normalization, byte backup, independent tags and deletion undo, including failure/retry.
3. Implement retained per-list presentation state, fixed quick composer, independent tag entry/management, single-choice edit flow, stable row actions and collapsible completed section. Cover IME explicitly.
4. Update affected tests from obsolete multi-tag/add-menu/confirmation contracts to new observable behavior, add meaningful regressions and dual-appearance renders. Build/test with xcodebuild -scheme Pulse -destination 'platform=macOS' using /tmp derived data; Swift 6 build is typecheck, use project formatting/lint if configured.
5. Independent trellis-check agent audits full diff against approved requirements and self-fixes defects. Main updates docs/builtin-tasks.md, README if needed, frontend state spec and backend task spec after implementation settles.
6. Native QA on isolated store, inspect renders; record precise commands/results and remaining limitations in task. Never modify actual Application Support/Pulse/tasks.json in tests. No publish/release/install.
7. Follow finish workflow, commit only task-related changes, leave unrelated .workbuddy and docs/images intact.
