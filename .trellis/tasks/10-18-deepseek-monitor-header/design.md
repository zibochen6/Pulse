# DeepSeek monitoring and leading-aligned header design

## Architecture and boundaries

Add a `DeepSeekProvider: UsageProviding` under `Features/Usage/Providers`. Its sole endpoint is `GET https://api.deepseek.com/user/balance`; the provider owns authentication, finite request timeout, HTTP error classification, typed response decoding, and decimal normalization. It returns existing `.balance(amount:currency:)` metrics, so UI code never reads response JSON and money never becomes quota percentage. Preserve separate balances for each currency; reject malformed/empty/duplicate-currency data rather than guessing or summing it. Accept complete valid decimal strings, including zero and reported negative amounts. Treat `is_available: false` as a successful reading when a valid balance is present.

Use an injected HTTP seam and `SecretStoring` for deterministic tests. HTTP 401/403 means invalid credentials, 429 means retry later, 404/405 means unavailable balance endpoint, and remaining non-success statuses mean service failure. Network, timeout, cancellation, and malformed responses remain explicit and never expose keys or raw response bodies.

The app delegate owns a separate DeepSeek credential configuration and `UsageController`, with a 600-second loop, launch refresh, 60-second stale refresh on popover open, and manual refresh. It passes the same observable controller to Home and Usage. Extend the existing test-host live-usage gate to cover the new controller. The system status item continues to observe Codex only.

## Credentials and reuse

Use the existing Keychain service with a new stable account `DeepSeek API key`. Save trims surrounding whitespace; remove touches only that account. Preserve the existing 88VIP account string and errors. Settings supplies a SecureField plus save/replace/remove controls and clears input after successful mutation.

Extract only repeated credential persistence/form behavior or compact status presentation that would otherwise be copied substantially; keep provider-specific endpoint, parsing, formatter choice, and messages explicit. Preserve the existing VIPConfiguration-facing API where practical so this feature does not force unrelated callers to change. Keep shared money formatting neutral rather than making DeepSeek depend on a VIP-named formatter.

A credential mutation invalidates any older in-flight result and guarantees a fresh request, even when a refresh was already active. Implement the smallest controller lifecycle seam that provides this guarantee, with tests for replace/remove while fetching. Do not leave an old successful balance visible after removal.

## Presentation

### Home

Retain existing text-first buttons, native colors, typography, settings gear, and Pulse identity. Use the actual DeepSeek whale mark matching the user's supplied reference, preserving its belly, eye, tail and negative-space details; a generic whale silhouette is not acceptable. The source vector extracted from `https://www.deepseek.com/` is saved at `research/deepseek-official-mark.svg`. Keep the original geometry, use the reference blue (`#4D6BFE`), fit proportionally inside the existing icon frame, and share it across Home/Usage/Settings. Prefer faithful native vector rendering over approximate hand drawing or runtime SVG dependencies. Add a descriptive accessibility label and stable `openDeepSeekUsageButton` identifier. A compact successful balance uses an unambiguous currency marker: `¥` for CNY and `$` for USD. With both currencies, prefer CNY in the summary and show each separately in Usage. Format at most two decimal places consistently with the existing balance summary; preserve exact Decimal data in the snapshot. Loading shows `…`; unavailable/error shows `!` with full guidance in Usage.

First header candidate: brand, tightly spaced provider controls, flexible spacer, settings. Moving flexible space after the provider controls shifts them toward the leading edge.

Fallback: brand and settings on the first row, then provider controls starting at the header's leading inset. Wrap complete controls into further leading-aligned rows if necessary. Use actual ideal widths and the available container width, rather than hardcoded assumptions about particular amounts. Reserve the settings hit area. Do not shrink fonts or truncate decimals to force a fit.

Only a single indicator whose ideal width exceeds the entire usable row may use a bounded horizontal scroll region. It must not force sibling indicators outside the popover. Normal one/two-window Codex values, 88VIP `$104.22`, and realistic DeepSeek balances must be visible in full without scrolling. Keep 360 × 510 as the AppKit/SwiftUI size and let the task region retain the remaining height.

### Usage and Settings

Append a DeepSeek Usage section with total balance rows labelled by currency, last update, manual refresh, loading, setup guidance, and explicit failure messages. Keep this page scrollable. A missing key directs the user to Providers settings.

Append DeepSeek credentials to Providers settings using existing Pulse action styles. Preserve the other settings and task-source behaviors. No separate window, account auto-import, or custom endpoint is added.

## Compatibility and rollback

No data migration, task-storage changes, menu-bar preference changes, or new external dependency is needed. Preserve all existing provider identities and Keychain accounts. Update source/test call sites deliberately; never construct a default production credential reader just to satisfy tests. Regenerate the Xcode project when adding Swift files.

Rollback can remove the new provider/controller/UI wiring and header layout change without modifying existing stored tasks, preferences, or keys. Do not automatically delete a saved DeepSeek key on upgrade/downgrade.

## Verification

Provider tests cover authentic request construction, full decimal parsing, native currencies, zero/negative balances, multiple currencies, empty/malformed fields, HTTP/network/timeout/cancellation errors, and secret-store failures. Credential tests cover save/replace/remove isolation and obsolete-result invalidation. Presentation checks cover each state in both appearances, actual non-overlapping control frames at 360 points, multiple quota windows, large balances, and representative rendered images. Run the full existing suite after integration and inspect README/spec consistency.

Real authenticated account verification is deferred until the user enters a key through Settings; automated tests use synthetic data only.

## Authorized 0.1.2 delivery

The user explicitly requested a new build/release, local installation, and cloud code publication. Use the existing repository `https://github.com/zibochen6/Pulse.git`, increment `project.yml` and the generated Xcode project to version 0.1.2/build 6, and add versioned release notes plus README download links. Scope is the reviewed feature and release preparation, not unspecified additional architecture work.

Preserve the current distribution channel: a universal macOS 13+ Release app signed with the locally available Apple Development identity already used by the installed build. Do not claim Developer ID signing or notarization. Package the exact verified app with an Applications link into `Pulse-0.1.2.dmg`, create its SHA-256 file, mount read-only to verify bundle version, signature and both architectures, then eject.

Before installation, retain the old app in a timestamped recoverable backup outside the repository. Gracefully terminate the installed Pulse, stage/verify the new bundle, replace `/Applications/Pulse.app`, and launch that exact path. Verify installed executable bytes and running process location; do not modify task files, preferences, or Keychain credentials. The running app may perform its ordinary account refreshes; automated acceptance still uses synthetic data.

Publish only task-owned files; exclude pre-existing `.workbuddy/` and `docs/images/`. Fetch remote state first and use fast-forward-only integration/non-forced pushes to the default `main` branch, plus a version tag pointing to the verified source commit. Create the GitHub release with the DMG and checksum and verify remote assets/tag after publication. Retain rollback information and do not rewrite existing tags or releases.
