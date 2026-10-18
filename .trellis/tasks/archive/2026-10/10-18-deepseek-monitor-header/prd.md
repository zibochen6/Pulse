# DeepSeek balance monitoring and left-aligned header

## Goal

Add DeepSeek account balance monitoring and move the popover provider statuses left without clipping amounts.

## Background

The user requested DeepSeek monitoring and moving the existing popover header indicators left, with screenshots highlighting the crowded end of the 88VIP amount. The current app has independent Codex and 88VIP usage controllers, a fixed 360 × 510 popover, provider settings backed by macOS Keychain, and a Codex-only system menu item.

## Requirements

- R1: Add optional DeepSeek account-balance monitoring through the official service. Display the reported currency and total balance without converting currencies, deriving a quota percentage, or inventing an amount when a request fails.
- R2: Provide a DeepSeek API-key field with save, replace, and remove actions in Settings → Providers. Store the key only in macOS Keychain and clear the form after successful save/removal. Other providers remain independent.
- R3: Show the actual DeepSeek whale mark matching the user's supplied reference beside Codex and 88VIP on Home; do not substitute a generic whale silhouette. Use the same mark on Usage and Settings. Clicking the status opens Usage details and requests a fresh reading. Usage shows all reported currency balances, update time, setup/error guidance, and manual refresh.
- R4: Move provider indicators toward the leading edge. Prefer one compact header row when it fits; otherwise keep the provider indicators left-aligned beneath the brand and allow complete provider indicators to wrap. Neither amounts nor settings controls may overlap, clip, or lose decimal digits.
- R5: Refresh DeepSeek at launch and every ten minutes, on popover open when older than 60 seconds, and immediately after credential changes or manual refresh. Requests must time out, and failures must replace stale numeric balances with an explicit setup/error state.
- R6: Preserve the 360 × 510 popover, existing task interactions, Codex menu-bar behavior, and current Codex/88VIP behavior.
- R7: Following the user's explicit request to rebuild/release, install locally, and publish code remotely, deliver Pulse 0.1.2 (build 6) as the next development-signed universal preview. Preserve a recoverable backup of the installed app, retain user data/settings/Keychain items, publish the task-owned source to the existing GitHub repository, and publish the versioned DMG plus checksum and release notes.

## Proposed Scope Boundaries

- Included: official DeepSeek API account total balances, native-currency presentation, credential settings, compact status, Usage details, leading-aligned adaptive header, focused automated verification, user documentation, and the explicitly requested 0.1.2 release/local installation/GitHub publication.
- Excluded: DeepSeek chat subscription monitoring, token/cost history, currency conversion, low-balance notifications, custom or reseller endpoints, changes to the system menu item, unrelated refactoring, and a new notarization/update-service workflow.
- Multi-currency balances remain separate. The compact summary prefers CNY if reported, otherwise USD; Usage lists every reported balance. Unavailable or malformed responses never become zero.

## Acceptance Criteria

- [x] AC1 (R1, R3): Synthetic CNY and USD responses produce correct decimal total balances with explicit currency, including zero and negative reported balances; multi-currency responses are neither summed nor converted.
- [x] AC2 (R2): Save/replace/remove use the DeepSeek Keychain account exclusively, clear successful form input, surface storage errors, and leave 88VIP credentials untouched.
- [x] AC3 (R3, R5): Loading, missing-key, authentication, rate-limit, network, timeout, malformed-response, and success states have appropriate compact and detail presentations; failed refreshes do not display an old balance as current.
- [x] AC4 (R4): At the existing popover width, Codex, 88VIP `$104.22`, and DeepSeek balances are complete, visibly shifted toward the leading edge, and independently clickable with settings reachable. Multiple Codex windows and large balances wrap whole indicators without overlap.
- [x] AC5 (R3–R6): Home, Usage, and provider settings render in Aqua and Dark Aqua; existing navigation/task tests continue to pass, and the system menu item remains Codex-only.
- [x] AC6 (R1–R6): Build, relevant tests, formatting checks, and visual inspection pass without accessing real account credentials in tests.
- [x] AC7 (R7): Version metadata and release notes agree on 0.1.2/build 6; the signed Release app contains arm64 and x86_64, the mounted DMG verifies signature/version/architectures/checksum, the same build is installed and running from `/Applications/Pulse.app`, and GitHub source/tag/release assets are published and verified.

## Review Status

Task creation and planning were approved on 2026-10-18. The user approved implementation, supplied the actual logo, and subsequently authorized release, local installation and remote publication. All acceptance criteria pass. Pulse 0.1.2/build 6 is installed and running; source commit `4b2a8083bbde1c98d87e173707349aa280b18cd8`, main/feature branch, annotated tag v0.1.2 and the public GitHub release with verified DMG/checksum are published. Task bookkeeping is ready for archival.
