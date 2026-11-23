# Antigravity Gemini usage

## Scenario: Check Gemini subscription quotas in Pulse

### 1. Scope

Use when changing the Antigravity CLI transport, Gemini quota normalization, opt-in refresh, or Gemini status card.

### 2. Signatures

- `AntigravityCLIReading.readUsage() async throws -> AntigravityCLIResult` returns the short-lived process result.
- `AntigravityProvider.fetch() async throws -> UsageSnapshot` supplies the same controller and lifecycle as the other providers.
- `QuotaWindow.bucketID` identifies one allowance independently of its duration. Older providers can omit it.

### 3. Contracts

- Resolve an executable `agy` through normal macOS install paths, the absolute entries in `PATH`, or the installed app helper. Require `agy --version` at least 1.1.11 before asking for a usage report.
- Run `agy --disable-slash-commands=false -p /usage --output-format json --print-timeout 12s` using fixed arguments and a private temporary working directory. Bound stdout, stderr and process lifetime. Cancel and reap the child when tracking is disabled. On abandonment, clean its confirmed process group even when a helper has outlived the launcher and still holds a pipe. Child-only overrides disable update and browser launch and exclude developer API keys. Preserve the existing Google sign-in and network environment.
- Parse `status == SUCCESS` and `command.name == usage`, then read `command.data.groups[].buckets[]`. Known IDs are `gemini-5h`, `gemini-weekly` and `gemini-argon-wtu-weekly`. Accept finite fractions in 0–1 and round to integer percent. Keep parseable `reset_time` even when the fraction is missing. Skip disabled or unrelated buckets. Keep both weekly allowances distinct.
- Store only the opt-in in Pulse preferences. Use an app-owned shared controller for setup, Home and Usage. Background refresh runs every 600 seconds while enabled. Disable invalidates in-flight or queued requests. Inject the offline runtime in the XCTest app host.
- Home selects `gemini-5h` by ID. Clicking the card opens a detail page with the reported target buckets, names, reset times and a manual refresh action. The native status item uses its existing Codex state.

### 4. Validation and errors

| Condition | Result |
| --- | --- |
| CLI missing, unsupported, signed out or ineligible | Localized unavailable state with the matching guidance |
| Query timeout, transport error, malformed output | Localized failure with retry available |
| Known bucket with reset and unknown fraction | Keep the reset and show an unknown percentage |
| No usable Gemini bucket | Quota unavailable |
| Only weekly data available | Home shows an unknown 5-hour value, detail shows weekly data |

An eligibility check can wrap a transport failure. Use explicit account or location denial text for the eligibility state and preserve timeout or network causes such as EOF.

### 5. Cases and tests

- A CLI report with 90% for 5 hours, 96% weekly and 100% Argon weekly shows 90% on Home and three labeled detail rows.
- Zero remains 0%. A missing percentage stays unknown and a disabled bucket cannot substitute for another bucket.
- Use synthetic reports and fixture executables to test version gating, timeout, cancellation, bilingual labels and ID-based selection. Run live CLI and UI smoke testing separately.

### 6. Selecting the Home metric

This window is identified by the allowance, even when only one weekly allowance is present:

```swift
let window = snapshot.quotaWindows.first {
  $0.bucketID == AntigravityQuotaBucket.fiveHour.rawValue
}
```

Selecting `quotaWindows.first` whenever `gemini-5h` is missing would label a weekly percentage as the Home metric.
