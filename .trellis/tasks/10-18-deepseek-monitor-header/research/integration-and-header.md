# Integration and header evidence

## Official API

Verified on 2026-10-18 through ego-browser against the [DeepSeek Get User Balance reference](https://api-docs.deepseek.com/api/get-user-balance).

- Request: `GET https://api.deepseek.com/user/balance`.
- Headers: `Authorization: Bearer <TOKEN>` and `Accept: application/json`.
- Response: `is_available` Boolean and `balance_infos` array.
- Each balance entry has `currency` (`CNY` or `USD`) and decimal-string `total_balance`, `granted_balance`, and `topped_up_balance` fields.
- `total_balance` already includes granted and topped-up balances. Do not add the components to it, divide it by 100, or convert between currencies.
- `is_available` describes whether the balance can fund API calls. A successfully reported zero balance is still a successful balance reading.
- The requested MVP uses total balances; component breakdown and spending history are deferred.

## Existing contracts and source owners

- `Pulse/Core/Usage/UsageSnapshot.swift`: generic `.balance(amount:currency:)`, `UsageProviding`, and loading/success/unavailable/failure states already exist.
- `Pulse/Core/Usage/UsageController.swift`: single-flight fetch, scheduling, stale refresh, and prior-success retention only while a fetch is in progress. A failed completed fetch replaces the old value.
- `Pulse/Features/Usage/Providers/VIPProvider.swift`: injected HTTP/secret seams, 20-second requests, status classification, and Decimal money parsing are useful patterns. Keep DeepSeek endpoint/response semantics separate.
- `Pulse/Core/VIPConfiguration.swift` and `Pulse/Core/SecretStore.swift`: Settings-facing credential actions, stable per-provider Keychain accounts, and no ordinary preference storage for keys.
- `Pulse/App/PulseAppDelegate.swift`: owns controllers; starts/stops them; refreshes stale balances on popover open; unit-test host disables live refresh through `PULSE_DISABLE_LIVE_USAGE`.
- `Pulse/Features/Home/HomeView.swift:5`: popover size is 360 × 510. Header at lines 64–84 puts a flexible spacer before the summary cluster in both candidates, pushing it right. Summary cluster at lines 158–173 is forced to its ideal width and does not wrap its children.
- `Pulse/Features/Home/AIStatusSummary.swift` and `VIPStatusSummary.swift`: text-first independent buttons with stable accessibility identifiers and full-width text sizing.
- `Pulse/Features/Usage/UsageView.swift`: existing per-provider sections and refresh controls.
- `Pulse/Features/Settings/SettingsView.swift`: existing Providers section, SecureField, save/remove actions, and Keychain-specific feedback.
- `Tests/PulseTests/HomeViewRenderingTests.swift`: synthetic providers, isolated defaults/storage, both macOS appearances, and image capture patterns.
- `Tests/PulseTests/VIPUsageTests.swift`: mock secrets and HTTP responses; do not use real keys or requests in tests.

## Historical decisions already persisted

The archived 88VIP task's `design.md` specifies that status controls may move below the brand when they do not fit the first row. This supports an adaptive header without changing the fixed popover size. Current product docs mention scrolling for wide quotas; the implementation and updated documentation must agree on whole-indicator wrapping and a bounded horizontal fallback for a single exceptionally wide quota label.

## Tooling and preservation

- Swift 6, macOS 13 minimum; local Xcode 27.0 is available.
- `xcodegen` and `xcrun swift-format` are available. No repository-specific swift-format or SwiftLint config was found.
- `project.yml` includes the Pulse and test source directories. Generate the checked-in Xcode project after adding source files.
- Existing untracked `.workbuddy/` and `docs/images/` predate this task; preserve them and exclude them from task commits.

## Focused risks

- A credential change during an in-flight fetch must invalidate the old result and schedule a request using the new/missing credential; the current single-flight guard alone would drop that request.
- A single large Codex summary can exceed an entire row. Moving the outer cluster alone is insufficient; constrain only that oversized control and make its full text horizontally reachable, while ordinary balances remain fully visible.
- Visual render success and opaque-pixel assertions alone do not prove that indicators are visible or non-overlapping. Capture element frames and inspect representative images.
- Do not present decimal strings parsed only up to an invalid suffix as real balances. Validate complete strings before constructing Decimal values.
