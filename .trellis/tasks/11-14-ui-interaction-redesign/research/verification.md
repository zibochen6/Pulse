# Implementation verification

Date: 2026-11-14. Source branch: `codex/ui-interaction-redesign`.

## Delivered behavior

- Fixed 400 × 520 popover, shared adaptive surfaces, violet/mint/apricot tag
  accents, consistent action hierarchy and provider-specific usage destinations.
- Singleton 720 × 560 categorized Settings window; app-owned task and credential
  presentation survives ordinary navigation and closing the window.
- Pinned intrinsic-width Todo, scroll overflow controls, selected-tag actions,
  searchable full-name manager, duplicate feedback, reorder and draft-safe delete.
- Action-specific motion, noninteractive outgoing page snapshots, reduced-motion
  geometry suppression, and source-scoped native menu/drag/editor dismissal holds.
- Truthful connection states and restart/quit preflight before installation;
  hidden drafts and pending writes prevent automatic installation.
- English and Simplified Chinese resources plus isolated native demonstration
  screenshots and 18-second animations in both languages.

## Native interaction observed

Used the opt-in `UIDemoExportTests.testInteractiveNativePreview` host with
synthetic accounts and a temporary task store. The host exited successfully
after its sentinel was removed. It does not replace the installed application.

The actual native interface visibly confirmed:

- Compact pinned Todo and overflow arrow controls on the home view.
- Selected-tag options menu with Rename, Delete, Move left and Move right.
- Manager rename form; setting a Chinese name and saving changed the row from
  `灵感` to `灵感清单`.
- Search narrowed the manager to the renamed tag.
- Settings opened as its own window with five categories and clear connection
  controls. Lists & tags showed the same renamed tag and retained search query.

Text was supplied through accessibility input, not composed with a Chinese IME.
The preview mounts the actual Home view in an ordinary native window; therefore
these observations do not establish real NSPopover pointer-departure timing,
outside-drop/Escape delivery, or menu-bar opening behavior.

## Automated verification

| Check | Result / evidence |
| --- | --- |
| Full integrated suite, English | **235 passed, 0 failed, 2 expected opt-in demo skips**; `/tmp/PulseRedesign-verified-tests.xcresult` |
| Chinese UI/localization/settings/layout suites | **24 passed, 0 failed**; `/tmp/PulseRedesign-zh-tests.xcresult` |
| Independent production + test build | Pass; `/tmp/PulseRedesign-review-build.log` |
| Release build, arm64, macOS 13 deployment target | Pass; `/tmp/PulseRedesign-release.log` |
| Strict formatting of 53 changed/new Swift files | Pass |
| English / Chinese resource syntax | Pass |
| Export script syntax, context manifests, diff whitespace | Pass |
| Native search focus regression | Pass; `/tmp/PulseRedesign-locator-tests.xcresult` |
| Actual tag-bar control bounds regression | Pass; `/tmp/PulseTagBar-targeted.log` |
| Bilingual native asset export | Pass; `/tmp/PulseRedesign-export-final.log`; 8 PNGs, 2 MP4s, 2 GIFs |

All results above include the final source changes. Two newly added
native-layout tests initially failed to locate their
controls despite those controls working in the visible native preview. Search
now locates the actual editable NSTextField rather than assuming SwiftUI's
accessibility identifier is mirrored onto it. Tag layout now uses passive
anchor preferences to measure actual control frames, with no test-only app
state: Todo stays below 80 pt, both arrows/add/manage stay inside the 400 pt
host with positive hit areas and no row overlap. Behavioral assertions remain
intact; unreliable AX traversal was removed.

## Promotion assets

`docs/media/ui-redesign/README.md` describes provenance and links every output.
The exporter uses real SwiftUI/AppKit views and actual controller actions, with
temporary data and inert external services. It is a reproducible product-view
demonstration, not a measured mouse interaction recording or frame-rate claim.
Both final MP4s are 1024 × 720, 540 encoded frames at 30 fps, exactly 18 seconds.
Final Chinese light Home, English dark Home, English dark Settings and Chinese
light Settings images were visually inspected after regeneration; fixed tag
controls, readable provider values and both language/theme layouts are present.
The eight outputs provide both themes for both surfaces in both languages.

## Remaining release acceptance

Manual runtime coverage remains outstanding for real menu-bar hover/open/close,
drag-outside and Escape cancellation, Chinese marked-text composition, and
supported macOS versions on their actual hardware. This session runs on macOS
27.0.1; a macOS 13 deployment target is not equivalent to runtime coverage there.
The initial implementation did not replace or publish the app. The user's
subsequent explicit delivery request authorizes an Apple Development-signed
0.1.8 release and local installation; delivery evidence is recorded separately.
Developer ID signing/notarization remains outside this task.
