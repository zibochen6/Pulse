# Integrate 88VIP quota

## Goal

Let a Pulse user connect an 88VIP account once and see its real remaining USD balance beside Codex in the popover, with full details and refresh controls on the Usage page.

## Confirmed facts

- Pulse currently owns one Codex `UsageController`, whose state drives both the macOS status item and the popover.
- The home header has room for compact status items; Tasks must remain the visually dominant content.
- 88API documents `GET /v1/dashboard/billing/subscription` and `GET /v1/dashboard/billing/usage`. The subscription limit is USD and `total_usage` is measured in USD cents.
- `my_dashboard` implements the same two requests, but its header renders a CNY symbol without currency conversion. Pulse must not copy that display behavior.
- The user chose a fixed 88API endpoint, a manually entered credential stored only in the macOS Keychain, popover-only display, and no Seeed integration in this task.

## Requirements

1. Add an 88VIP provider that requests the documented subscription and usage endpoints using the saved credential and calculates remaining USD as limit minus used amount.
2. Display a compact color 88VIP icon and short USD amount to the right of Codex in the popover header. It opens Usage details when clicked.
3. Keep the system status item as Codex-only and do not change Codex data retrieval behavior.
4. Add Provider settings to enter, replace, or remove the 88VIP API key. The key is stored only in Keychain and never in UserDefaults, logs, documentation, or test fixtures.
5. Show accurate states for unconfigured, loading, successful, partial response, invalid key, rate limit, network failure, endpoint failure, and malformed response. Missing data must render as `--`; unlimited quota may render as an explicit unlimited state.
6. Refresh 88VIP at launch and every ten minutes. Reopening the popover refreshes only when the last data is stale; Usage provides manual refresh. Requests must not overlap.
7. Usage detail shows limit, used, remaining, access expiry when supplied, update time, and specific errors.

## Out of scope

- Seeed, custom provider endpoints, cc-switch or `my_dashboard` credential imports.
- Changes to the Codex provider, system status item, Tasks, Obsidian, database, or networking third-party libraries.
- Currency conversion and any write operation against 88API.

## Acceptance criteria

- [ ] A saved 88VIP key produces a USD remaining value from mocked subscription and usage responses, with cents divided by 100 exactly once.
- [ ] Header states are compact, accessible, and render correctly beside one-window and multi-window Codex summaries in light and dark appearances.
- [ ] No saved key produces a clear setup state; invalid, rate-limited, network, endpoint, and malformed responses produce distinct user-facing failures without exposing the key.
- [ ] The Usage page displays 88VIP detail and supports independent manual refresh while preserving existing Codex controls.
- [ ] Test doubles cover Keychain save/read/delete and no automated test requests a real 88API account.
- [ ] The project builds and its full unit-test suite passes.

## Open questions

None. The user approved the final plan for implementation on 2026-09-29.
