# Codex usage integration contract

## 1. Scope / Trigger

Use this contract when changing Pulse's local Codex usage reader, quota normalization, refresh behavior, or menu bar readout. The source is the installed Codex CLI app-server. It is separate from future OpenAI Platform billing adapters.

## 2. Signatures

```swift
protocol UsageProviding: Sendable {
  func fetch() async throws -> UsageSnapshot
}

protocol CodexAppServerReading: Sendable {
  func readRateLimits() async throws -> Data
}

struct UsageSnapshot: Sendable {
  let providerID: String
  let fetchedAt: Date
  let metrics: [UsageMetric]
}
```

`CodexProvider` maps the app-server response into a provider-neutral `UsageSnapshot`. `UsageController` owns `@Published state` on the main actor and prevents overlapping refreshes. `UsageMenuFormatter` maps that same state to the status item title; `UsageView` renders it in the popover.

## 3. Contracts

- Launch `codex app-server --listen stdio://`; send newline-delimited `initialize` with `clientInfo` and id 1, await a successful result, then send `initialized` and `account/rateLimits/read` with id 2. Match responses by id. The process is bounded by a timeout and terminated after the response.
- CLI discovery checks `CODEX_BIN` exclusively if set, then known ChatGPT.app / Codex.app bundle layouts, common install paths, and `PATH`. A bad override is an error.
- Accept `result.rateLimitsByLimitId.codex` or a legacy `result.rateLimits` whose `limitId` is `codex` or absent. Never use another limit ID as Codex quota.
- Windows come from `primary` and `secondary`; `usedPercent` is optional. Compute `remainingPercent = round(100 - clamp(usedPercent, 0...100))`; missing or non-finite values remain unknown. Preserve valid `windowDurationMins` and `resetsAt` (Unix seconds). Use reported windows, not `planType`, for display.
- One reported window displays only its percentage; multiple windows display short duration labels. An unknown percentage displays `--`, never zero. Quota is distinct from balance/cost metric kinds.
- Refresh at launch and every 60 seconds while running. A refresh failure replaces the prior success state so stale numbers are not shown as current. The app reads no authentication files and logs no raw responses or account identifiers.
- XcodeGen's `Pulse` test scheme sets `PULSE_DISABLE_LIVE_USAGE=1` for the app test host. `PulseAppDelegate` must check it before calling `UsageController.start()`. Unit tests assert the marker is present, so they cannot accidentally query a real Codex account when XCTest launches the host app.

## 4. Validation & Error Matrix

| Condition | Result |
| --- | --- |
| No executable in discovered locations | Unavailable, with CLI guidance |
| Invalid explicit `CODEX_BIN` | Distinct error naming the override; no fallback to another binary |
| Process cannot launch or exits before reply | Error state |
| Handshake/request rejected | Error state, sign-in guidance |
| Timeout | Error state and retry option |
| Malformed JSON or unexpected response shape | Error state |
| No Codex limit or no known percentage | Unavailable; no invented value |
| One or two valid windows | Success; menu and popover share the same snapshot |

## 5. Good / Base / Bad Cases

- Good: `codex` has five-hour and weekly windows; menu reads `5h 66% 7d 63%`, popover names each reset.
- Base: one weekly window; menu reads `98%`, popover explains its duration and reset.
- Bad: another limit ID reports usage but Codex does not; menu reads `--` and explains no Codex quota.

## 6. Tests Required

Use synthetic JSON and mock transports/providers only. Assert legacy and keyed responses, single and dual windows, unknown percent, clamping, reset preservation, refusal to substitute a different limit ID, server error/malformed/no quota, distinct CLI override behavior, provider-neutral non-quota snapshots, and success-to-error state clearing. Assert `PULSE_DISABLE_LIVE_USAGE=1` in the test host and that it disables startup refresh. No automated test should access a real account.

## 7. Wrong vs Correct

```swift
// Wrong: silently use an unrelated limit when Codex is absent.
let selected = rateLimitsByLimitId.values.first

// Correct: require Codex's keyed limit or a compatible legacy limit.
let selected = rateLimitsByLimitId["codex"] ?? compatibleLegacyRateLimits
```
