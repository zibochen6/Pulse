# Validation evidence

## Real-store isolation baseline

Captured read-only before tests; tests must leave the real store unchanged.

```json
{
  "exists": true,
  "sha256": "d6e00f855d72745b294ec7db61c3267ca45805f2aa933f00e6560b6c59d45c90",
  "size": 979
}
```

## Checks

- Native Computer Use selection of Pulse failed with timeoutReached (-10005); actual native mouse/input-method acceptance remains unverified pending retry.
- AppKit text-edit probe: an NSTextView hosted by NSWindow handles Undo/Redo through window responder actions; editor contents restored correctly.

- Native Computer Use retry: inventory works, but selecting SystemUIServer also timed out (-10005). No native input actions were issued.
- `xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/PulseTodoMenuDerivedData CODE_SIGNING_ALLOWED=NO -only-testing:PulseTests/PulseApplicationMenuTests test`: 3 tests passed, zero failures. Log `/tmp/PulseTodoMenuTests.log`.
- Strict swift-format lint passed for edited AppKit menu/menu tests.

- Full UI source build passed (`/tmp/PulseTodoUIBuild.log`). Launched only the development executable with `PULSE_DISABLE_LIVE_USAGE=1`; test PID 72879 used an isolated temporary store. Computer Use selection by exact development bundle path still timed out (-10005). Terminated only that QA PID; production Pulse PID 99970 was left running.

- First full suite passed: 169 tests, zero failures (`/tmp/PulseTodoFullTests.log`, xcresult `/tmp/PulseTodoMenuDerivedData/Logs/Test/Test-Pulse-2026.10.20_21-23-49-+0800.xcresult`). Additional independent-review corrections require a final rerun.
- Reviewed `/tmp/PulseTaskInteractionRender/NSAppearanceNameAqua-list.png` and `NSAppearanceNameDarkAqua-options.png`: fixed tabs/input, list content, collapsed options and Undo fit within task region without visible overlap. Reviewer additionally inspected Aqua editor/new-tag renders.
- Real-store SHA256 after tests still matches baseline: True.

## Final gate

- Final full suite: **175 tests, zero failures**, exit 0. Log `/tmp/PulseTodoFinalScrollRegression.log`; xcresult `/tmp/PulseTodoMenuDerivedData/Logs/Test/Test-Pulse-2026.10.20_21-42-39-+0800.xcresult`. Swift 6 / macOS Debug build included.
- Main independently ran strict swift-format lint on all **11 changed/new Swift files**, exit 0, plus `git diff --check`, exit 0.
- 20 interaction/render tests include actual hosted TaskEntryField Undo/Redo visible-string AND binding assertions, inherited disabled state, marked-text submit protection, per-list retained drafts and stale save/new-ID behavior, independent tag creation, collapsed completed reveal and edit/tag snapshot guards. A real NSHostingView/NSWindow regression with 40 tasks verifies the actual native scroll viewport moves to the target after editor-to-list mounting, and reveal requests are consumed once.
- 12 new storage tests cover byte backup failure/recovery, legacy normalization, standalone tag retry, single-list rejection, transaction-current delete receipts, missing-tag restore/conflicts, uncertain-delete retry and bounded 20-item LIFO.
- 20 Aqua/Dark Aqua interaction state images regenerated under `/tmp/PulseTaskInteractionRender`. Main also inspected full Home integration at `/var/folders/m9/q_604zm12glft_dyqknk7jbc0000gn/T/PulseBuiltinTaskRender/NSAppearanceNameAqua-home.png`; task/header/input fit at 360x510. Copy for chat preview: `/Users/chenzibo/.codex/visualizations/2026/10/20/01a1594a-f8a1-7281-9686-ecc810d8ae51/todo-tag-preview.png` (synthetic test data).
- Real-store SHA256 still equals baseline after final suite. Production app/data not replaced during QA.

## Remaining validation limitation

Native desktop selection repeatedly timed out for Pulse, SystemUIServer and the exact isolated dev bundle. No actual desktop mouse or Chinese input-method candidate flow could be exercised. Native AppKit text-field Undo/Redo and marked-text delegate gating passed automated tests; these are not a claim of full live-desktop acceptance.

## Independent final review

Trellis check agent independently verified the final source, actual-scroll regression and 175/0 final log. All actionable findings fixed; quality gate **pass**, with the live-desktop limitation above retained. No duplicate full-suite run was performed by the reviewer.
