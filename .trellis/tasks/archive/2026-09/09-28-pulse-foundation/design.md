# Technical Design

## Application boundary

Use a native Xcode app target named Pulse with deployment target macOS 13, `LSUIElement` enabled, and no sandbox entitlement for the first GitHub download build. AppKit owns the app delegate, `NSStatusItem`, a small menu, and a placeholder window. The menu exposes Open Pulse and Quit. Keep code intentionally small; future SwiftUI screens can be hosted from the AppKit shell.

No empty local Swift package or SQLite database is created in Phase 0. When actual provider and Markdown logic exists, extract platform-independent domain/integration logic into a local package and add meaningful unit tests. The future app stores nonsecret preferences via system defaults, provider secrets in Keychain, and treats Vault Markdown as the source of truth.

## Public documentation

README is English-first with a short Chinese summary and clear distinction between the current shell and planned MVP. `docs/01` is a source-grounded analysis of local `codex-usage-status`. `docs/02` records architectural decisions. `docs/03` describes Vault integration without hardcoded folders, using only aggregate, non-identifying observations from the private Vault. `docs/04` designs a provider protocol that returns typed metric capabilities instead of forcing balances and rate windows into one percentage. `docs/05` describes optional Vault onboarding and a target note chosen once. `docs/06` specifies phase gates. `docs/07` covers public positioning and launch preparation without claiming an existing release.

## Key future contracts

- Provider refresh is asynchronous and yields a snapshot with metric kind (rate window, currency balance, periodic cost, or unavailable), freshness, and an actionable error state. Configuration references a Keychain item, never stores its value in plain text.
- Vault selection uses a user-selected folder. Task discovery scans Markdown without assuming Daily or Projects locations. Only ordinary `- [ ]` / `- [x]` tasks are safe to toggle in the first write-capable release; complex Tasks plugin semantics remain in Obsidian.
- Task writes must reread/revalidate source before a single-line mutation and abort on concurrent modification. Tests use temporary Vault copies, never the personal Vault.

## Compatibility and operational notes

GitHub download is the initial distribution path. Developer ID signing and notarization are release gates later, not part of this task. The Codex integration remains behind the local official CLI/app-server boundary; API provider capability depends on each service's documented authentication and usage endpoints. The remote repository is empty, so the first Pulse commit establishes `main`.
