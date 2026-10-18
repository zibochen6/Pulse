# Verification evidence

## Implementation checks

- Xcode Debug build/type-check: passed, `/tmp/PulseDeepSeek-build.log`.
- Full suite: 194 tests, 2 existing DashboardTaskRowTests accessibility skips, 0 failures. Final log: `/tmp/PulseDeepSeek-full.log`.
- Result bundle: `/tmp/PulseDeepSeekDerivedData/Logs/Test/Test-Pulse-2026.10.18_09-32-10-+0800.xcresult`.
- All 20 Swift files changed by the implementation pass strict `swift-format` lint.
- `git diff --check`: passed.
- New coverage: 12 DeepSeekUsageTests and 2 DeepSeekRenderingTests, including synthetic HTTP/Keychain data, native currencies, invalid values, provider failure states, replace/remove during fetch, cancellation before fetch cleanup, and measured header bounds.

## Visual and layout review

Main session inspected the following synthetic images:

- `/tmp/PulseDeepSeekRender/NSAppearanceNameAqua-home-1-windows.png`
- `/tmp/PulseDeepSeekRender/NSAppearanceNameDarkAqua-home-1-windows.png`
- `/tmp/PulseDeepSeekRender/NSAppearanceNameAqua-home-3-windows.png`
- `/tmp/PulseDeepSeekRender/NSAppearanceNameDarkAqua-CNY-and-USD-usage.png`
- `/tmp/PulseDeepSeekRender/NSAppearanceNameAqua-settings-all-controls.png`

At the fixed 360-point width, normal fallback controls begin at x=14, 78, and 158, with the gear at x=318. The `$104.22` and `¥42.68` sample balances display all digits. Wide balances wrap whole controls; the new frame tests also cover the small-value single-row case and a bounded 20-window quota label. Aqua/Dark Aqua renders preserve the opaque app surface and existing task region.

## Acceptance mapping

| Criterion | Evidence |
| --- | --- |
| AC1: native monetary data | Decoder and formatter tests cover CNY/USD, zero/negative, multi-currency preference, strict malformed/duplicate/unknown rejection |
| AC2: independent credentials | In-memory account-isolation and keychain failure tests; shared form clears text on successful save/remove |
| AC3: visible refresh states | Provider/formatter/state tests, actual state renders, obsolete-generation and early-cancellation regressions |
| AC4: leading complete indicators | Actual SwiftUI anchor bounds, non-overlap/text-width assertions, and visual inspection |
| AC5: appearances and regressions | Aqua/Dark Aqua Home/Usage/Settings renders and the full existing suite |
| AC6: quality and account isolation | Build, formatting, diff-check, test-host live-usage gate, injected synthetic stores/providers |

## Remaining verification boundary

No real DeepSeek key was supplied, so authenticated live-account verification was not performed. Configure the key through Settings → Providers in the newly built app. The user's installed app was not replaced or restarted, and pre-existing `.workbuddy/` and `docs/images/` remain untouched.

## Independent review

The separate `trellis-check` pass found no defects and made no code changes. It independently passed strict lint for all 20 changed Swift files, Xcode build/type-check (`/tmp/PulseDeepSeek-review-build.log`), and `git diff --check`, and reviewed the full-suite evidence. Source/project registration and docs/spec consistency passed. Commit confirmation and task archival remain.

## User-requested icon correction

The user rejected the first simplified whale and supplied the actual DeepSeek mark. The shared icon now renders the exact original vector path from the official website, proportionally centered with the reference blue `#4D6BFE` and nonzero fill preserving the belly/eye cutouts. Source geometry and retrieval notes are retained under `research/`; third-party notices identify the official source.

- Correction build/type-check: passed, `/tmp/PulseDeepSeek-icon-build.log`.
- Focused `DeepSeekRenderingTests`: 2 tests, 0 failures, `/tmp/PulseDeepSeek-icon-render-tests.log`.
- Correction strict formatting and `git diff --check`: passed.
- Main visually inspected enlarged Aqua/Dark Aqua component images at `/tmp/PulseDeepSeekIconRender/NSAppearanceNameAqua-official-icon.png` and `NSAppearanceNameDarkAqua-official-icon.png`, and refreshed Home/Usage renders. They match the supplied reference and preserve existing header bounds.
- Full 194-test suite remains the preceding integration evidence; the icon-only correction does not change provider, storage, refresh, or layout behavior and does not require a redundant full rerun.
- Independent correction review: passed with no findings or edits. All 80 native path operations match the original SVG, including the expanded vertical segment; aspect fit, color, fill, shared use, and attribution were confirmed.

## Authorized 0.1.2 release delivery

- Source/project/bundle metadata agree on 0.1.2/build 6. README/tag/DMG names and release notes passed independent metadata review.
- Universal Release build passed: `/tmp/PulseRelease-0.1.2-build.log`; executable contains arm64 and x86_64, minimum macOS 13.
- Signed with the existing Apple Development identity/team used by the old installed app. Strict signature verification passed. This is the existing development preview channel, not Developer ID/notarized distribution.
- Release executable SHA-256: `abf8611041fc5c14f90a8657c699857698b67c8c590c79945160d2d538544fe8`.
- DMG: `/tmp/PulseRelease-0.1.2/dist/Pulse-0.1.2.dmg`, 2,426,575 bytes. SHA-256: `185441b8cc22fe31e287771f4b27b8aff12d393bc4be124378d192ea79efdba6`; its `.sha256` file verifies successfully.
- Image verification and read-only mounted-payload checks passed: 0.1.2/build 6, strict signature, both architectures, executable/plist/signature-resource equality, Applications link. The image was ejected.
- Staged installation was verified before graceful termination of the old app. Old 0.1.1/build 5 was retained under `~/Library/Application Support/Pulse/Application Backups/Pulse-0.1.1-build5-20261018-095057.app`.
- `/Applications/Pulse.app` now contains the verified signed 0.1.2/build 6 binary; one process runs from `/Applications/Pulse.app/Contents/MacOS/Pulse`.
- Native desktop inspection via Computer Use timed out. The installed bundle/process checks and existing synthetic renders do not certify native menu interaction. No Gatekeeper or other security setting was changed.
- GitHub repository/default branch confirmed; remote main was fetched through the existing system proxy and matches the current base. v0.1.2 did not exist at preflight. Source/tag/release publication verification is pending.
