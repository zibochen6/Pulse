# Phase 2A: Codex usage integration

Pulse's first real usage source is the locally installed Codex CLI. This phase connects the existing Codex menu bar icon to the quota windows reported by `codex app-server`. It does not query the OpenAI Platform API, handle API keys, or connect Obsidian.

This Phase 2A implementation is the Codex status milestone called **1B** in the original [MVP roadmap](06-mvp-roadmap.md); provider expansion remains a later milestone.

## Source and protocol

The implementation was checked against the locally cloned [codex-usage-status](https://github.com/tollenceld/codex-usage-status) macOS source: `CodexUsageFetcher.swift` for process/stdio handling, `CodexBinaryLocator.swift` for CLI discovery, `UsageModels.swift` and `UsageWindowKind.swift` for normalization, and `AppDelegate.swift` for refresh/display behavior. The local reference uses `initialize` (id 1), `initialized`, then `account/rateLimits/read` (id 2) over newline-delimited JSON, and recognizes legacy `rateLimits` plus the newer `rateLimitsByLimitId` response. Pulse retains the same native status-item design but keeps the usage domain separate from UI and deliberately avoids selecting a different limit ID as a Codex fallback.

The [official Codex App Server documentation](https://developers.openai.com/codex/app-server/) documents the initialize handshake, stdio JSON lines, and `account/rateLimits/read`, including `usedPercent`, `windowDurationMins`, and `resetsAt` for primary and secondary windows. This is a local CLI protocol rather than a service-wide API quota. Pulse reads no authentication files.

A read-only probe of the installed CLI during this implementation returned a successful `account/rateLimits/read` response with both legacy and `codex` keyed fields and one reported primary window. The probe printed only response shape, never account values or identity. The build and automated tests do not depend on that account.

## Data flow

```text
Codex CLI → app-server JSON line → Codex decoder → UsageSnapshot
                                                   ↓
                                     refresh state/controller
                                        ↙              ↘
                                  NSStatusItem       SwiftUI Usage
```

The provider-neutral usage model distinguishes quota windows from balances, costs, and unavailable data so a later provider can report its real unit. Codex currently yields quota windows only. A missing `usedPercent` stays unknown; a missing window is never inferred from a plan name. The menu bar shows only the remaining percentage for one reported window (for example `98%`), and short labels for multiple windows (for example `5h 66% 7d 63%`). Reset times and refresh details belong in the popover. Loading, no reported quota, and fetch errors use clear nonnumeric states.

## Refresh and failure behavior

Pulse fetches at launch and periodically while it runs. One refresh is active at a time. CLI not found, process launch failure, timeout, a server error, malformed JSON, and no quota data must be distinguishable to the user; the icon and popover remain usable. The menu bar never converts an error into `0%` or a fabricated quota. A failed fetch should not present an old percentage as current.

The popover has a **Refresh** action. Launching a development build can have a different `PATH` from a terminal; the CLI locator therefore checks known app bundles and standard install locations in addition to `PATH`, with `CODEX_BIN` as an explicit override for development. A wrong override produces a distinct error instead of silently choosing another binary.

## Verification and limits

Automated tests use synthetic app-server responses and a mock provider. The XcodeGen test scheme sets `PULSE_DISABLE_LIVE_USAGE=1` before the Pulse test host launches, so startup cannot query the installed CLI during unit tests. Tests assert that the host received this flag. They cover response shapes, window count/formatting, error paths, and refresh state without touching the user's account. The Debug build, strict Swift format lint, and 20 tests passed during this phase; commands are in the README. A separate sanitized live smoke test of Pulse's own transport returned one known Codex quota window; it did not output account values. Visual inspection of the status item and popover was unavailable while the Mac desktop was locked. A later manual check should confirm the menu bar value, popover details, periodic updates, error wording, click-away dismissal, and no Dock icon on macOS.

The local app-server contract and Codex app bundle layout can change. If Codex is not installed or the user is not signed in with an eligible ChatGPT account, Pulse should explain the problem and preserve the menu bar entry. Cancelling an in-flight refresh does not stop its subprocess immediately; the current read deadline is 10 seconds. Immediate cancellation will need a transport lifecycle owner and process tests. Future provider APIs and source-specific icon selection are outside this phase.
