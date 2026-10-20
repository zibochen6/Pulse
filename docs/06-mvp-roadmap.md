# MVP roadmap

Phases are ordered by risk and user value. Each phase has a concrete gate; a public downloadable MVP follows Phase 3, after both AI status and the local task list work. Dates are intentionally unset until the integration tests establish effort.

| Phase | Goal and features | Acceptance | Main risk |
| --- | --- | --- | --- |
| **0 — Project initialization** | Native macOS 13+ shell, reproducible Xcode project, README/license, source-based architecture and ecosystem research. | App builds and launches; docs distinguish current from planned behavior. | Build settings and initial trust claims may drift from implementation. |
| **1A — Menu Bar foundation** | Native status item with an honest `--%` no-data readout, transient SwiftUI popover with Usage/Tasks placeholders, Quit, UserDefaults preferences, and macOS login item integration. | Build and unit tests pass; icon and placeholder readout remain visible, popover, click-away dismissal, Dock absence, and Quit are checked; actual login status is not confused with the saved request. | Login item approval and development-build behavior vary by machine. |
| **1B — Codex status** | Detect installed Codex CLI, read local rate-limit state through app-server, show remaining quota directly beside the Codex icon, with window selection, freshness, missing-login and missing-CLI states. | Tested with available and unavailable CLI, one/two/unknown windows, timeout, retry, sleep/wake; one window shows only its percent, multiple windows use short labels; no auth-file scraping or secrets in logs. | Local CLI or response shape changes. |
| **2 — Provider system** | Add typed provider snapshots, Keychain credentials, scheduler/error states, source-specific menu bar icons, and first verified API adapters. DeepSeek balance is a practical early candidate; OpenAI/OpenRouter administrative access must be optional and explained. | Different metric kinds display with real units; a deliberate source-selection rule keeps the menu bar compact; normal keys are never falsely promised privileged billing access; one provider failure does not block another. | Permission scopes, icon licensing, rate limits, provider API changes, and user trust. |
| **3 — Obsidian Todo** | **Removed from scope.** This phase described a user-selected Vault, checkbox discovery, safe toggle/add and conflict handling against Markdown files. That integration was removed; the shipped native to-do list (tag tabs, quick add, visible completed rows, daily repeat) covers the MVP task path, and its acceptance lives in [built-in tasks](builtin-tasks.md). | No remaining acceptance gate for this phase; see the built-in task acceptance checklist. | Scope was dropped rather than deferred; keeping it would reintroduce concurrent-editor risk. |
| **4 — Enhancements** | Better filters/search, richer provider coverage after verification, task grouping, and polished visuals. | User-requested additions retain data safety and accessible performance; each adapter has a documented capability test. | Scope expansion and maintenance load. |

## Public MVP gate

Before a broader public MVP: Phase 1A–2 and the shipped built-in task
acceptance pass; a fresh-machine install
is signed with Developer ID and notarized; privacy/key handling is reviewed;
documentation includes screenshots, an accurate feature matrix, installation
instructions, known limits, and a way to report issues. GitHub currently offers
development-signed previews with DMG checksums and release notes; they do not
claim notarization or completion of these wider acceptance gates.

The user's menu bar display requirements and the lessons from the local reference iteration are recorded in [menu bar status requirements](08-menu-bar-status-requirements.md).
