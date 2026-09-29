# Technical design: 88VIP quota

## Boundary

`VIPProvider` owns the 88API wire contract and turns decoded, validated response fields into provider-neutral usage metrics. `UsageController` remains the scheduling and published-state owner. A small Keychain-backed credential controller owns the API key lifecycle. SwiftUI renders already-normalized data and never parses JSON or reads secrets.

```
Settings input -> Keychain credential store -> VIPProvider -> UsageController
                                              -> UsageSnapshot -> header / Usage detail
```

The Codex provider, its refresh interval, and the macOS status-item subscription remain unchanged.

## Contracts

- `SecretStoring` supplies `read`, `save`, and `delete` operations behind an injectable Keychain implementation. The fixed account name is internal to the 88VIP configuration owner.
- `VIPProvider: UsageProviding` calls the fixed HTTPS base URL. The subscription response chooses the first positive `hard_limit_usd`, `soft_limit_usd`, or `system_hard_limit_usd`; the usage response converts `total_usage` from cents to USD. It never sends a generation request.
- `UsageMetric` gains generic allowance and usage amount variants so the Usage page can show limit, used, and remaining without provider-specific raw JSON. Existing quota formatting remains untouched.
- `UsageController.refreshIfStale(maxAge:)` reads the last successful snapshot timestamp and uses its existing in-flight guard. Only the 88VIP controller uses this behavior.
- A successful subscription with an unavailable usage response is a partial snapshot: it shows the allowance and a precise unavailable metric; it does not invent a remaining balance. A subscription failure produces a typed refresh error.

## UI and lifecycle

- `PulseAppDelegate` owns a second controller with a ten-minute interval and starts it alongside Codex. It triggers a stale check when the popover opens.
- The home header lays out Codex and 88VIP status as individual compact controls. If they cannot fit on the first row, they move together to a short status row immediately below the identity row. Tasks remains below and keeps the available height.
- The Usage page has independently refreshable Codex and 88VIP sections. Settings has a focused 88VIP credential form and an explicit saved/unsaved indicator.
- The color 88VIP artwork is bundled for popover use only; it is not template-rendered or used in the system status bar.

## Failure and safety behavior

- Missing key is an unavailable setup state. HTTP 401/403, 429, 404/405, URL/network errors, and decoding errors map to distinct messages without response-body or secret logging.
- Keychain write/read/delete failures remain local to Settings and do not break Codex or the popover.
- The app stores no balance cache in this task. A failed refresh replaces a previously displayed 88VIP value with its explicit failure state, matching Pulse's current non-stale Codex behavior.

## Rollback

Removing the new provider, Keychain configuration, and bundled icon returns Pulse to its existing Codex-only behavior. Existing UserDefaults remain untouched.
