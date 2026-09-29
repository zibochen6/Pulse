# 88VIP provider integration

Pulse can show an optional 88VIP remaining balance in its popover. It uses the documented 88API billing endpoints and the same data interpretation verified in the local `my_dashboard` reference: the account limit is USD and `total_usage` is measured in USD cents.

## Configuration

Open **Settings → Providers**, paste an 88VIP API key, and select **Save key**. Pulse stores the key as a generic-password item in the macOS Keychain. It does not inspect cc-switch, `my_dashboard`, shell environment variables, or private note files.

Use **Remove key** to stop future 88VIP requests and remove the stored credential. Pulse never writes the key to UserDefaults, logs, tests, documentation, or provider snapshots.

## Display and refresh

The system menu bar remains Codex-only. Pulse shows a colored 88VIP mark and a compact USD value beside Codex inside the popover header. Selecting either value opens the Usage page, where 88VIP reports its limit, used amount, remaining balance, supplied access expiry, update time, and an independent refresh control.

Pulse requests 88VIP at launch and every ten minutes. Opening the popover runs a refresh only when the previous snapshot is at least ten minutes old. A manual refresh does not overlap an active request.

## Accuracy and failures

The provider reads the first positive `hard_limit_usd`, `soft_limit_usd`, or `system_hard_limit_usd`. It computes `remaining = max(0, limit - total_usage / 100)`. If the usage endpoint is unavailable, the limit remains visible but remaining displays `--`. A missing finite limit is displayed as **Unlimited** rather than as a money amount.

Pulse distinguishes missing or invalid credentials, rate limiting, unsupported billing endpoints, network failures, server failures, and malformed payloads. A failed refresh replaces the prior 88VIP value with its explicit status, so an old amount is never presented as current.
