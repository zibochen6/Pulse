# Local reference analysis: codex-usage-status

This analysis is based on the locally cloned `codex-usage-status` source under `macos/CodexUsageStatus/` as inspected on 2026-09-28. Paths below are relative to that reference repository. The reference uses MIT (its root `LICENSE`). Phase 1 bundles its `CodexMenuIcon.png` artwork with attribution in [third-party notices](../THIRD_PARTY_NOTICES.md); no reference application source code is copied.

## Architecture

| Concern | Observed implementation |
| --- | --- |
| Entry point | `Sources/CodexUsageStatus/main.swift` handles `--doctor` and `--once`, then creates `NSApplication`, assigns `AppDelegate`, and runs it. The native target is an SPM executable (`macos/CodexUsageStatus/Package.swift`); repository packaging turns it into an app. |
| Lifecycle and menu bar | `App/AppDelegate.swift` sets accessory activation, owns `NSStatusItem` and `NSMenu`, installs Refresh, display settings, Settings, and Quit actions. The status button displays a template icon plus text or a rendered badge. |
| UI | AppKit owns menus and an `NSAlert` diagnostics/settings dialog. `UI/UsageBadgeRenderer.swift` draws ring/readout images; `UI/CodexMenuIcon.swift` loads a bundled icon with a system-symbol fallback. No SwiftUI screen is present in this implementation. |
| Refresh | `AppDelegate.refresh()` guards overlapping calls, runs `CodexUsageFetcher.fetch()` asynchronously, records last success/error, and schedules a one-shot timer. `App/Configuration.swift` defaults to 60 seconds and retries failures after 15, 30, 60, then 300 seconds. Manual Refresh uses the same path. |

## Codex integration and data flow

1. `Codex/CodexBinaryLocator.swift` searches an explicit `CODEX_BIN` override, Codex.app bundle metadata/known layouts, and `PATH`. The override fails visibly if wrong instead of falling through silently.
2. `Codex/CodexUsageFetcher.swift` launches the local executable as `codex app-server --listen stdio://`. It writes newline-delimited JSON-RPC messages: `initialize` (with `experimentalApi`), `initialized`, and `account/rateLimits/read` with request id 2. There is no direct call to a public web usage API and no reading of an auth file.
3. `ResponseBox` buffers stdout, selects only the response for id 2, handles an RPC error, and decodes `RateLimitsResponse`. A 20-second timeout terminates the child process. `FetchError.swift` provides localized errors for missing CLI, timeout, server error, invalid output, and missing response.
4. `Domain/UsageModels.swift` accepts both `rateLimitsByLimitId` and legacy `rateLimits`, scores snapshots, normalizes windows, clamps used percentage, derives remaining percentage, and keeps missing values unknown. `UsageWindowKind.swift` classifies common 5-hour and weekly windows while preserving custom/unknown durations. `Domain/QuotaDisplayMode.swift` controls display selection and explains fallback when the requested window is unavailable.
5. The delegate renders a placeholder before the first result, a red/`?` error state after failure, and a tooltip with plan, windows, credits, and last refresh context. On failure it retains the last successful `UsageSummary` in memory but renders the error state; Pulse should explicitly design stale-data display rather than accidentally hide freshness.

Source anchors: `main.swift`; `App/AppDelegate.swift` lines 7–80, 187–257; `App/Configuration.swift` lines 3–23; `Codex/CodexBinaryLocator.swift` lines 14–103; `Codex/CodexUsageFetcher.swift` lines 47–119 and 122–195; `Domain/UsageModels.swift` lines 3–55 and 141–216.

## Reuse decisions

| Reuse or adapt | Why |
| --- | --- |
| Local CLI discovery with a clear diagnostic path | Codex.app bundle paths change; a single locator isolates that volatility. |
| One refresh path with overlap prevention, last-success metadata, and bounded retries | A long-running menu bar process needs predictable polling and understandable stale/error states. |
| Typed decoding and capability-aware window normalization | A provider response may omit windows or add new durations; absence must not be shown as zero. |
| Native status item and template symbol conventions | These fit macOS menu bar behavior and appearance. |

| Do not adopt directly | Why |
| --- | --- |
| Codex-only menu model and percentage badge as the universal UI | Pulse must represent balances, spend, and tasks alongside rate windows. |
| AppKit `NSAlert` as the full settings experience | Multi-provider and Vault setup need guided, accessible screens; future content/settings will use SwiftUI inside an AppKit shell. |
| Fixed plan-name inference from window combinations | This is reference-project display logic, not a stable identity contract for every plan or provider. |
| Shell/environment-only configuration as the public onboarding path | Pulse targets ordinary users who should not need CLI flags or paths. |

If future Pulse work copies any reference code, retain the reference project's MIT copyright and license notice as required by its `LICENSE`; prefer adapting the idea behind its boundaries and testing against the installed Codex version.

The user's earlier iteration established additional presentation requirements: the icon must render as a macOS template icon, one quota window needs only its percentage in the menu bar, and multiple windows need short labels. Those requirements and future provider implications are captured in [menu bar status requirements](08-menu-bar-status-requirements.md).
