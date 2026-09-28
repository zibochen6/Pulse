# MVP roadmap

Phases are ordered by risk and user value. Each phase has a concrete gate; a public downloadable MVP follows Phase 3, after both AI status and Obsidian tasks work. Dates are intentionally unset until the integration tests establish effort.

| Phase | Goal and features | Acceptance | Main risk |
| --- | --- | --- | --- |
| **0 — Foundation** | Native macOS 13+ menu bar shell, reproducible Xcode project, README/license, source-based architecture and ecosystem research. | App builds and launches, menu bar opens a placeholder and Quit exits; docs distinguish current from planned behavior. | Build settings and initial trust claims may drift from implementation. |
| **1 — Menu Bar + Codex** | Detect installed Codex CLI, read local rate-limit state through app-server, show windows, freshness, missing-login and missing-CLI states. | Tested with available and unavailable CLI, one/two/unknown windows, timeout, retry, sleep/wake; no auth-file scraping or secrets in logs. | Local CLI or response shape changes. |
| **2 — Provider system** | Add typed provider snapshots, Keychain credentials, scheduler/error states, and first verified API adapters. DeepSeek balance is a practical early candidate; OpenAI/OpenRouter administrative access must be optional and explained. | Different metric kinds display correctly; normal keys are never falsely promised privileged billing access; one provider failure does not block another. | Permission scopes, rate limits, provider API changes, and user trust. |
| **3 — Obsidian Todo** | User-selected Vault, ordinary checkbox discovery, target note selection for Add, safe toggle/add, external-change refresh, open-in-Obsidian for complex Tasks lines. | Use temporary Vault fixtures for UTF-8/CRLF, duplicate lines, conflicts, rename/delete, and plugin metadata; no lost external edits. First-run path reaches real status and tasks within five minutes in usability checks. | Concurrent editors and sync, plugin semantics, large Vault scan cost. |
| **4 — Enhancements** | Better filters/search, richer provider coverage after verification, optional Tasks plugin support, task grouping, launch-at-login and polished visuals. | User-requested additions retain data safety and accessible performance; each adapter has a documented capability test. | Scope expansion and maintenance load. |

## Public MVP gate

Before publishing a GitHub release: Phase 1–3 acceptance passes; a fresh-machine install is signed with Developer ID and notarized; privacy/key handling is reviewed; documentation includes screenshots, an accurate feature matrix, installation instructions, known limits, and a way to report issues. Phase 0 is source code only and makes no release claim.
