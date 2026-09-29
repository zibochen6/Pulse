# 88VIP usage integration contract

## 1. Scope / Trigger

Use this contract when changing Pulse's 88VIP balance integration, its macOS Keychain credential, the documented 88API billing requests, or balance normalization. The integration is popover-only: the system status item remains Codex-only.

## 2. Signatures

```swift
protocol SecretStoring: Sendable {
  func read(account: String) throws -> String?
  func save(_ secret: String, account: String) throws
  func delete(account: String) throws
}

protocol VIPHTTPClient: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct VIPProvider: UsageProviding {
  func fetch() async throws -> UsageSnapshot
}
```

`VIPConfiguration` is the sole Settings-facing owner of the fixed Keychain account. `VIPProvider` reads it through `SecretStoring`, uses `VIPHTTPClient` for the fixed service URL, and returns generic `UsageMetric` values. `UsageController` owns refresh state and schedule.

## 3. Contracts

- The only supported base URL is `https://88api.ai/v1`. Requests are `GET /dashboard/billing/subscription` and `GET /dashboard/billing/usage`, with `Authorization: Bearer <key>` and `Accept: application/json`. Do not add a user-configurable endpoint or import a key from another tool.
- Read the first positive value among `hard_limit_usd`, `soft_limit_usd`, and `system_hard_limit_usd` as the USD allowance. `access_until`, when positive, is a Unix timestamp in seconds.
- `total_usage` is USD cents. Normalize it exactly once: `usedUSD = total_usage / 100`; normalize `remainingUSD = max(0, allowanceUSD - usedUSD)`. Money stays a `UsageMetric` allowance, usage, or balance; never reuse a percentage quota window for a money value.
- A subscription with no positive limit produces `.unlimited`, optionally with `.expiresAt`. If the subscription works but Usage fails, return a partial snapshot with the allowance and `.unavailable(reason:)`; do not fabricate a remaining amount.
- The app delegate owns a separate 88VIP `UsageController`, starts it at launch, refreshes it every ten minutes, and calls `refreshIfStale(maxAge: 600)` when showing the popover. Its failures must not change the Codex controller or the system status item.
- API keys live only in the macOS Keychain. Never put a key in UserDefaults, a snapshot, an error message, a log, a fixture, or documentation. The Settings form clears its in-memory text after a successful save or remove.

## 4. Validation & Error Matrix

| Condition | Result |
| --- | --- |
| No saved Keychain item | Unavailable setup state with Settings guidance |
| Keychain read/write/delete error | Settings reports a Keychain-specific error; Codex remains usable |
| HTTP 401 or 403 | Invalid credentials |
| HTTP 429 | Rate-limited |
| HTTP 404 or 405 | Billing endpoint unavailable |
| Other HTTP status | Service status error, without response-body logging |
| Transport failure | Network failure |
| Invalid JSON, missing or negative `total_usage` | Invalid response |
| Usage request fails after valid subscription | Partial snapshot; show limit and `--` remaining |
| Subscription has no finite positive limit | Explicit unlimited state |

## 5. Good / Base / Bad Cases

- Good: `hard_limit_usd: 100` and `total_usage: 1234` display limit `$100`, used `$12.34`, and remaining `$87.66`.
- Base: a valid subscription has `soft_limit_usd: 25` but usage is rate-limited; show `$25` as the limit and `--` as remaining.
- Bad: a saved key receives 401; replace any prior header balance with `!` and show credential guidance in Usage.

## 6. Tests Required

Use an in-memory `SecretStoring` and mock `VIPHTTPClient`; no test may access a real Keychain item or account. Assert cents conversion, limit fallback, no invented remaining after partial failure, unlimited state, malformed response, each HTTP classification, network failure, key save/replace/remove, stale refresh behavior, compact summary states, and Aqua/Dark Aqua rendering for loading, success, unavailable, and failure.

## 7. Wrong vs Correct

```swift
// Wrong: total_usage is cents, so this turns 1234 cents into $1,234.
let remaining = limit - totalUsage

// Correct: convert exactly once before calculating USD remaining.
let usedUSD = totalUsage / 100
let remainingUSD = max(0, limit - usedUSD)
```
