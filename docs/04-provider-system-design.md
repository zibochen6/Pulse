# Provider system design

## One interface, distinct capabilities

AI services do not expose a single universal “quota percentage.” Pulse's future adapter boundary should return typed observations with the data source, collection time, and failure/freshness state. An illustrative Swift contract (design, not current code):

The menu bar should pair the selected source's icon with a compact value in its real unit. The popover may show every configured source. A later Provider phase must decide how users select the one menu bar source, verify icon redistribution rights, and test each icon in light and dark menu bars; see [menu bar status requirements](08-menu-bar-status-requirements.md).

```swift
protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func refresh(configuration: ProviderConfiguration) async throws -> ProviderSnapshot
}

struct ProviderSnapshot: Sendable {
    let providerID: String
    let observedAt: Date
    let metrics: [UsageMetric]
}

enum UsageMetric: Sendable {
    case rateWindow(usedPercent: Double?, duration: TimeInterval?, resetsAt: Date?)
    case balance(amount: Decimal, currency: String)
    case periodicCost(amount: Decimal, currency: String, start: Date, end: Date)
    case unavailable(reason: String)
}
```

The actual implementation should make metric provenance, source scopes, and error types explicit before shipping. `nil` means unknown, never zero. A balance is not converted to a percentage without a verified limit. A cost is not labeled “remaining.” A snapshot can contain multiple windows or currencies.

## Configuration and key storage

Each configured provider has an ID, user-visible name, enabled state, refresh policy, provider-specific nonsecret options, and optional Keychain item reference. Only the secret lives in Keychain, protected by macOS access controls; configuration, diagnostics, crash reports, and logs must never contain the raw key. Codex's local connection does not require an API key. The UI explains requested permissions and offers a test connection before saving.

Custom OpenAI-compatible endpoints require a user-entered HTTPS base URL and explicit capability selection or a separately verified usage endpoint. OpenAI-compatible *generation* wire format does not imply compatible billing or usage endpoints. Do not send a test generation request merely to infer a balance.

## Verified adapter boundaries

| Provider | Documented path / limit | Design implication |
| --- | --- | --- |
| Codex | The local reference project calls `codex app-server` and `account/rateLimits/read` (see [01](01-reference-analysis.md)); the boundary is local CLI behavior, not a stable public usage REST contract. | Discover CLI, show unavailable when missing or logged out, and version-test the response. |
| 88VIP | `GET /v1/dashboard/billing/subscription` provides USD limit fields and `GET /v1/dashboard/billing/usage` provides `total_usage` in USD cents ([88API billing module](https://88api.ai/en/docs/api/api-modules/fei-account-billing-panel/)). | Store the user key in Keychain; calculate remaining USD as a verified limit minus `total_usage / 100`. Missing usage means unknown remaining, not zero. |
| DeepSeek | `GET /user/balance` returns currency-specific `balance_infos` and availability ([DeepSeek docs](https://api-docs.deepseek.com/api/get-user-balance/)). | Show balance per currency; avoid inventing a reset window. |
| OpenAI API | `GET /organization/costs` documents cost buckets and an `OPENAI_ADMIN_KEY` example ([OpenAI Costs endpoint](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs)). | Elevated Admin keys are optional and clearly labeled. A normal project key should not be promised account-wide spend or remaining credit. |
| OpenRouter | `GET /api/v1/credits` reports total purchased and used credits and requires a Management key ([OpenRouter docs](https://openrouter.ai/docs/api/api-reference/credits/get-credits)). | Explain management-key scope; show supported credit figures, not a generic rate percentage. |
| GLM | No specific balance endpoint or authentication scope is validated in this Phase 0 research. | Keep adapter planned; verify official API documentation and a permitted test account before making product claims. |
| Custom API | No universal billing contract follows from OpenAI-compatible inference. | Show “usage unavailable” until an explicitly configured and tested usage adapter exists. |

## Refresh and errors

Each adapter owns its minimum polling interval and any server rate-limit hints; the scheduler performs an initial refresh, allows manual refresh, prevents concurrent fetches per provider, and applies bounded exponential backoff with jitter after transient errors. Respect `Retry-After` where provided. Sleep/wake and network changes trigger a stale check, not an immediate burst of all requests. Cache the last successful snapshot with its time and display **Last updated** and **Stale** clearly.

Use actionable error categories: missing credentials, invalid credentials, insufficient permission, rate-limited, network unavailable, service error, unsupported capability, and malformed response. A provider failure does not block other providers or Obsidian tasks. Never log authorization headers, response bodies containing sensitive account data, or task text. Tests should cover missing fields, extra metrics, multiple currencies, HTTP 401/403/429, timeout, and provider-specific payload changes using fixtures rather than real user keys.

Codex and the fixed 88VIP adapter are implemented. Other provider adapters remain planned until their official billing capability and permission scope are verified.
