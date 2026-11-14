# Independent review

Reviewer: `trellis-check`, 2026-11-14. Reviewed approved PRD/design and actual
window, updater, native input, tag, provider-state and motion paths.

## Findings (fixed)

1. **Pending reorder could block Quit/Restart after navigation.**
   `LocalTasksView.swift`: successful move completion depended on mounted tag
   views observing the document. Switching to Usage before the write completed
   left `pendingTagOrder` active. Both drag and button completions now finalize
   presentation state directly. Added an off-page successful-write regression.
2. **Disabled test/demo hosts still reached real services from manual controls.**
   `PulseAppDelegate.swift`, new `PulseRuntimeServices.swift`: startup credential
   refresh read the real Keychain, and click/open refresh paths could query real
   providers despite disabled startup loops. Runtime dependency selection now
   substitutes inert secrets, providers, login registration and update services.
   Production dependencies are unchanged. Tests exercise refresh, credential
   invalidation, stale refresh and isolated service selection.
3. **All-tags search did not hold hover dismissal.**
   `LocalTagSettingsView.swift`: search focus now participates in editing holds.
   The retained query remains session UI state, not an unsaved task draft.
   Added a native NSTextField focus/input/blur regression. Its native locator
   now asserts the idle manager's single editable field instead of assuming
   SwiftUI's accessibility identifier is copied onto the bridged AppKit view.
4. **Reduce Motion still animated layout.**
   `ProviderCredentialForm.swift`, `LocalTasksView.swift`: a short ease-out on
   expansion/list switching still interpolated geometry. These layout animations
   are disabled under Reduce Motion; composer, undo and add-entry transitions
   explicitly omit translation. The body snapshot keeps its permitted fade.
5. **Retired task editors could write into a later editing session.**
   `LocalTasksView.swift`: the existing-task TextEditor binding was the remaining
   unguarded draft setter. It now checks its captured creation identity before
   accepting native text callbacks. Added native late-notification coverage after
   save and after another task is opened.
6. **Changed-file formatting failed.**
   Formatted only changed/new Swift files. Removed the redundant explicit
   `UpdateInstallPlan` initializer; the synthesized initializer retains the same
   parameters and default wait value. No untouched files were formatted.

## Findings (not fixed)

No additional confirmed functional defect remains from this review. Native
mouse, drag-cancellation, hover timing and real IME acceptance are still separate
from model/render tests and are being exercised by the root session.

The proposed NSMenu stale-end issue was not substantiated: tracking notifications
are consumed synchronously and the same native menu cannot begin a second
tracking session before its first ends. Existing independent hold/lease tests
cover overlapping sources and stale explicitly identified sessions.

## Verification

- Strict changed/new-file `swift-format` lint: **pass**, 53 Swift files.
  Log: `/tmp/PulseRedesign-review-format.log`.
- `git diff --check`: **pass**.
- Pre-review integrated suite (root): 229 tests, zero failures, one expected
  opt-in demo-export skip. This result predates reviewer fixes.
- Post-review type-check/build: **pass**. Independent `xcodebuild build-for-testing`
  completed in `/tmp/PulseRedesignReviewDerivedData`; log:
  `/tmp/PulseRedesign-review-build.log`. This checks production and test sources.
  Existing warnings remain in untouched `LocalTaskStorageTests.swift` (a `var`
  can be `let`) and the Xcode 27 XCTest framework deployment target.
- Post-review final full suite (root): **235 passed**, zero failures, two
  expected opt-in demo skips; `/tmp/PulseRedesign-verified-tests.xcresult`.
  Chinese UI/localization/settings/layout suites: **24 passed**, zero failures;
  `/tmp/PulseRedesign-zh-tests.xcresult`. Root coordinated all final test hosts.
  Earlier native test-locator failures were corrected without weakening the
  assertions: editable-field lookup for search and actual anchor-based control
  bounds for the tag bar. The final passive geometry hook/test also received
  independent review; it adds no app state or layout changes.
- Runtime CUA (root): Chinese tag rename/save, search filtering, opening Settings
  and sharing the renamed tag/query were exercised. Real NSPopover hover timing,
  native drag cancellation and live IME composition are not claimed as verified.
- Release build (root): **pass**. Final full-suite rerun follows the independent
  tag-layout locator correction; no reviewer test failure remains.
- New regression tests are in existing `LocalTasksRenderingTests.swift` and
  `SettingsLifecycleTests.swift`; the new runtime file requires project generation
  and was explicitly handed to root for `xcodegen generate`.

## Spec follow-up

Root should retain two executable contracts in UI/state documentation: async
reorder completion releases pending state without a mounted observer, and the
disabled runtime substitutes dependencies for manual actions as well as startup
loops. No storage schema or provider API contract changed.

## Final documentation consistency pass

Reviewed README, UI layout, motion, built-in task, auto-update and UI spec docs.
Reported five concrete stale groups: missing-key Connect behavior, actual
credential button names, updater button names/staged skip visibility, Settings
Move Up/Down labels, and first-custom-tag drop geometry. Root corrected all five.
No additional concrete stale statement was found in the motion or UI spec docs.
