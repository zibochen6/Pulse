# Validation

- Full macOS Debug XCTest suite: **180 tests, zero failures**. Log `/tmp/PulseMinimalTodoTests.log`; xcresult `/tmp/PulseMinimalTodoDerivedData/Logs/Test/Test-Pulse-2026.10.21_07-07-48-+0800.xcresult`.
- Strict `xcrun swift-format lint --strict` passed for both changed Swift files; `git diff --check` passed. Main verified independently after final changes.
- Presentation tests cover trailing entry expansion/collapse, exact-success collapse, per-list retained drafts, changed/reopened draft stale-response protection and hidden-draft hover dismissal.
- Native hosted AppKit tests cover initial field focus, actual scroll viewport, collapse teardown, undo/redo, inherited disabled state, IME command gating and late end-edit callback after new-tag staging. Existing storage/controller/daily-repeat/undo/popover tests remain green.
- 28 Aqua/Dark Aqua images generated in `/tmp/PulseMinimalTodoRender`. Main inspected list, editor (both appearances), Dark Aqua options and Aqua editor new-tag. Subtle adaptive editor fill and controls fit without overlap.
- Isolated QA executable launched with `PULSE_DISABLE_LIVE_USAGE=1`, PID 52460. CUA inventory succeeds, but exact dev-bundle selection fails `-10005 timeoutReached`. Stopped only this isolated process. Actual desktop mouse and Chinese IME candidate flow remain unverified; automated marked-text tests do not establish live IME acceptance.
- Real-store bytes unchanged against read-only baseline: True. No production app replacement or release publication.

## Independent review

Trellis check quality gate: **pass**. Native end-edit callback and Escape focus findings fixed and regression-tested; no remaining actionable code findings. Live desktop acceptance limitation retained above.
