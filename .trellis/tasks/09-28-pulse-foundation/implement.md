# Implementation Checklist

1. Confirm the new independent Pulse repository and empty `origin`; keep the parent repository untouched.
2. Add only a minimal native Xcode menu bar app, project metadata, `.gitignore`, MIT license, and truthful README.
3. Analyze the local reference Swift sources and write `docs/01-reference-analysis.md` with precise source anchors and MIT reuse notes.
4. Write `docs/02` through `docs/07`; use official sources for ecosystem/API claims and read the private Vault only for aggregate validation.
5. Build with `xcodebuild`, launch the app, verify its process/menu bar behavior and Quit action if practical, then stop it.
6. Check links, contents, absence of private paths or secrets, Git diff, and staged file list. Fix any concrete issues.
7. Commit all Pulse-owned deliverables using the user-specified exact message and push to `origin/main`.

## Change boundary

Phase 0 changes only the Pulse repository: a launchable shell, project metadata, Trellis task artifacts, and research docs. No provider requests, Codex calls, Vault writes, or key storage code is introduced. The pre-existing Trellis bootstrap task remains separate.

## Review and rollback points

- Confirm the Xcode project is self-contained and does not point at user-specific paths.
- Before commit, inspect every staged file and verify no private Vault data is included.
- If launch validation is not possible in the desktop environment, record exactly which build/launch checks succeeded and which UI behavior remains unverified.
