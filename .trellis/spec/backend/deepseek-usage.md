# DeepSeek balance integration contract

## 1. Scope / Trigger

Use this contract when changing DeepSeek balance requests, its Keychain credential, monetary normalization, or refresh lifecycle. This integration reports official API account total balances in the popover. The macOS status item remains Codex-only.

## 2. Signatures

```swift
struct DeepSeekProvider: UsageProviding {
  func fetch() async throws -> UsageSnapshot
}

protocol DeepSeekHTTPClient: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

enum DeepSeekUsageDecoder {
  static func decode(_ data: Data, fetchedAt: Date? = nil) throws -> UsageSnapshot
}

@MainActor final class DeepSeekConfiguration: APIKeyConfiguration {
  nonisolated static let keychainAccount = "DeepSeek API key"
}

// Shared by credential-based providers, with generation-guarded publication.
@MainActor final class UsageController: ObservableObject {
  @discardableResult func credentialsDidChange() -> Task<Void, Never>
}

protocol SecretStoring: Sendable {
  func read(account: String) throws -> String?
  func save(_ secret: String, account: String) throws
  func delete(account: String) throws
}
```

The external request is `GET https://api.deepseek.com/user/balance` with `Authorization: Bearer <key>` and `Accept: application/json`. `URLSessionDeepSeekHTTPClient` is the production transport. Decode at the provider boundary and return provider-neutral `.balance(amount:currency:)` metrics; views must not inspect response JSON. `APIKeyConfiguration` shares credential persistence with VIP while retaining each subclass's fixed account.

## 3. Contracts

- Use the fixed official endpoint and a 20-second request timeout. Never import another tool's credentials or accept a reseller/custom base URL through this integration.
- `balance_infos` is an array of records whose `currency` is `CNY` or `USD` and whose `total_balance` is a decimal string. `total_balance` already includes granted and topped-up balances; use it directly without adding components or dividing by 100. Parse complete strings into `Decimal`, never partial numeric prefixes or binary floating-point intermediates.
- Keep each currency separate. Never sum CNY and USD, relabel one as the other, or convert them. The compact summary prefers CNY when present, otherwise USD; Usage lists all reported balances with explicit currency. A valid zero or reported negative balance is data, not a failed request.
- `is_available` describes ability to fund API requests. A false value with valid reported balances must not hide those balances or turn them into a network failure.
- Reject malformed/empty balance data and duplicate-currency entries instead of inventing a zero or choosing an arbitrary duplicate. Preserve the snapshot's exact monetary values and set `fetchedAt` after response handling completes.
- The DeepSeek Keychain account is `DeepSeek API key`, separate from `88VIP API key`. Keys live only in Keychain and the temporary SecureField text, never UserDefaults, snapshots, logs, fixtures, or errors. Clear form text after successful save/remove.
- The app delegate owns an independent DeepSeek `UsageController`: refresh at launch and every 600 seconds, refresh when opening the popover if older than 60 seconds, and refresh immediately on manual action or credential mutation. The test-host `PULSE_DISABLE_LIVE_USAGE=1` gate must disable its live startup too.
- A successful background refresh may keep its prior balance visible while fetching. Completed failures replace it with an explicit error/setup state. Credential replacement/removal additionally invalidates older in-flight results and schedules a fresh fetch; a single-flight guard must not silently discard that request.

## 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Missing or whitespace-only key | Unavailable setup state with Providers settings guidance; no HTTP request |
| Keychain error | Explicit storage error without exposing a key |
| HTTP 401/403 | Invalid credentials |
| HTTP 429 | Rate-limited, retry guidance |
| HTTP 404/405 | Balance endpoint unavailable |
| Other unsuccessful HTTP status | Service-status error without raw response-body logging |
| Network/timeout | Retryable failure, finite busy state |
| Cancellation | No obsolete state publication |
| Invalid JSON, missing/empty balances, malformed decimal, unsupported/duplicate currency | Invalid response; no invented amount |
| Valid balance with `is_available: false` | Successful balance reading |
| Credential changes during a fetch | Old result cannot publish; new/missing credential is fetched |

## 5. Good / Base / Bad Cases

- Good: CNY `total_balance: "42.68"` produces `.balance(amount: 42.68, currency: "CNY")` and a compact `¥42.68` reading.
- Base: both CNY and USD are returned; Home chooses CNY and Usage shows both separately. A zero balance still displays zero.
- Bad: a replaced key's slow response arrives after a new key was saved; reject the obsolete result and fetch with the current credential instead of displaying the old balance.

## 6. Tests Required

Use synthetic responses and injected HTTP/secret stores only. Assert request URL, authorization/accept headers, timeout, full decimal parsing, native CNY/USD, zero and negative values, multi-currency ordering, duplicate/unknown/empty/malformed data, HTTP classifications, transport failure, cancellation, and Keychain failures. Cover save/replace/remove account isolation and replace/remove during an in-flight fetch. Existing Codex/VIP refresh and formatting tests must keep passing. UI verification covers all states in both appearances and includes actual layout measurements plus representative rendered images.

## 7. Wrong vs Correct

```swift
// Wrong: DeepSeek already reports a currency-unit total, unlike 88API usage cents.
let remaining = totalBalance / 100 + grantedBalance + toppedUpBalance

// Correct: preserve the reported total and its currency as one monetary metric.
let metric = UsageMetric.balance(amount: totalBalance, currency: currency)
```

Official source: [DeepSeek Get User Balance](https://api-docs.deepseek.com/api/get-user-balance), verified 2026-10-18.
