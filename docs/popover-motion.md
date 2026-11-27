# Motion and response

The native 400-point menu-bar popover fits a short paired Today list and caps
its content at 520 points. Settings uses a separate 720 × 560 window. Each
window keeps one live surface over its native backdrop.

| State change | Response |
| --- | --- |
| Press or keyboard focus | Immediate fill or focus indication |
| Release or hover | 90 ms release, 120 ms hover, stable hit area |
| Route or status change | 140 ms opacity feedback, input available immediately |
| Composer or drop | Immediate entry focus and local zero-bounce options or reorder feedback |
| Task completion | 180 ms checkbox and strike-through feedback |
| Async activity | Static idle glyph until 150 ms, then a fixed-size busy glyph |
| Scroll, drag, glass, timer values | Direct feedback |

A route change ends the outgoing field editor and immediately mounts the next
body, which can continue an interrupted fade from its current opacity. Drafts
live in the shared presentation. The panel applies one latest matching height
without starting a window resize animation. A staged update uses the full
available height.
Reduce Motion makes custom feedback immediate, disables native popover motion
and drag return animation, and uses a static busy glyph.

The inline Todo composer already has a native field before Add is pressed.
The action transfers first responder to the field editor in the same event.
A request remains pending until that editor is confirmed. Published draft
state follows committed input. AppKit keeps marked text and selection across
layout and bridge refreshes.

Quick Copy confirms a successful plain-text pasteboard write in the row's
existing trailing slot. The latest click owns the 1.4-second confirmation and
its timer. Under Reduce Motion, the same confirmation appears immediately.

## Pointer lifecycle

Opening waits for the 300 ms guard and AppKit's didShow. Departure from the
panel, arrow and menu-bar corridor starts a single 180 ms delay. Re-entry
cancels it. Editing, keyboard navigation, menu tracking and native dragging
hold dismissal independently. A pointer click in the panel ends the keyboard
hold. The 50 ms reconciliation loop pauses while held and immediately checks
geometry after the final release.

AppKit finishes its native close before Pulse handles a queued status click.
Additional clicks update the intended final state. Settings and exit cancel
queued reopening. On cancel or drop, the native drag session releases its hold
and stops edge scrolling.

## Runtime acceptance

Use an isolated development build and sample store. Exercise quick toggles,
pointer re-entry, native menus, keyboard focus, Chinese marked text, editing
and undo. Check short, 11-to-12 and long Today lists, update staging, rapid
navigation, status and error changes, and tag edge scrolling and cancellation.
Inspect both appearances, both languages, Reduce Motion and Reduce
Transparency. Screenshots and XCTest establish geometry and state, while
visible input checks establish interaction.

`UIDemoExportTests.testProfileVisibleMotion` is an opt-in native profiling test.
Build `Pulse` for testing in Release with `ENABLE_TESTABILITY=YES`. Run only this
test with `TEST_RUNNER_PULSE_MOTION_PROFILE` pointing to an empty output directory
and `TEST_RUNNER_PULSE_MOTION_SCREEN` selecting an `NSScreen` index. Use an
unlocked console and the normal isolated test scheme. After `ready.json`
appears, attach Instruments Hitches and Core Animation Commits to its PID,
create the `go` file, and wait for `intervals.json`. Create `finish` after
saving the trace. The first trial warms caches. Compare the following three
active intervals per scenario against the same fixture on the baseline.
The Quick Copy sweep contains 60 synthetic entries and uses a named test
pasteboard. Profile it as a new scenario.
Display-link callback cadence and compositor hitch time describe different
parts of the update and are reported separately.
