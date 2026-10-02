# Popover motion and response

## Behavior

Pulse keeps the 360×510 task-first layout and opaque adaptive background. The
popover uses macOS's native presentation/dismissal animation. Its precise effect
and duration are system-owned; Pulse does not promise a custom collapse into the
menu bar icon. Reduce Motion disables animation, including when the preference
changes while Pulse runs. Pulse never changes system accessibility settings.

| Setting | Previous | Current |
| --- | --- | --- |
| Minimum opening protection | 1 second | 300 ms, also waiting for native presentation completion |
| Pointer departure grace | 400 ms | 180 ms |
| Geometry reconciliation | 100 ms | 50 ms while shown |
| Native motion | Disabled | Enabled unless Reduce Motion is requested |

Actual departure detection can add up to one reconciliation interval when AppKit
omits an exit event. Native dismissal then takes its own animation duration. The
180 ms interval is the grace before the close request, not a guaranteed total
time until the window disappears.

## Lifecycle

`PopoverHoverController` owns Closed, Opening, Interactive, PendingClose and
Closing. Opening finishes only after the minimum guard and `popoverDidShow`.
At that boundary the actual pointer position is reread. Interactive includes
the status button, content and whole window, including the popover arrow.

A pending close is scheduled once. Duplicate exit events and geometry updates
cannot extend its deadline. Re-entry cancels it. The deadline checks actual
position again before requesting close. Editing retains the existing hover
suspension; outside clicks and status-item toggles do not wait for hover timing.

A close request enters Closing and cancels all work. Native outside dismissal
does the same in `popoverWillClose`. Late show/tracking events and rapid clicks
cannot restart or reverse a closing animation. `popoverDidClose` resets hover
and page navigation so Home is ready for the next opening. The displayed page
remains mounted during dismissal, avoiding a page-change flash.

## Validation

The final build and full regression run passed: **113 tests, 111 passed, 2
skipped, 0 failures**. The two existing skips are hosted SwiftUI accessibility
action tests whose surface exposes no buttons. The directed hover suite also
passed all 19 tests. Strict Swift formatting and `git diff --check` passed.
Unit tests cover timing, cancellation, missing events, repeated exits, arrow geometry,
edit suspension, immediate close, stale callbacks and closing reset. A native
NSPopover integration test checks actual didShow/willClose/didClose callbacks
with animation enabled and disabled. It passed in the final run; intermediate
attempts while the graphical session was locked failed to receive didShow. The
test now explicitly skips locked/non-console sessions and allows a longer wait
for system-owned animation callbacks, without changing application timing.
Existing rendering tests passed for Aqua/Dark Aqua and opaque edges with
fictional data; their generated Home images were inspected.

The previous Pulse process was stopped and the new `/tmp/PulsePopoverMotion`
build launched. Its executable path was verified; the system Reduce Motion
setting was false. Computer Use still could not read the accessory app: the
exact new app path timed out, and the bundle identifier had matched multiple
existing builds on an earlier attempt. Actual mouse delivery, rapid status-item
clicking, visual animation and live editing behavior remain unverified. The
native callback test is not a substitute for those checks.

## Manual acceptance

1. Open the new build and click the status item; keep the pointer there for two
   seconds. The popover should stay open.
2. Move into the popover and switch a column/filter or Settings. It stays open.
3. Leave both regions; after a short grace, native dismissal should be visible.
   Return within the grace and confirm dismissal is cancelled.
4. Repeatedly click the status item: a closing animation should finish without
   reopening or flashing. The next deliberate click opens Home.
5. Open a task editor. Departure alone should keep the draft open; an outside
   click may dismiss it. Reopening should retain the existing draft behavior.
6. With the user's Reduce Motion preference enabled, opening/closing should
   have no motion. Do not change accessibility settings during automated tests.

No task data, quota fetching, parser, source selection, typography or layout is
changed by this update. Existing uncommitted built-in task work is retained.

## Follow-up: Dashboard re-selection

The existing Settings action called `NSOpenPanel.runModal()` directly from the
transient popover, without activating Pulse or waiting for native dismissal.
That left the file chooser competing with popover focus/closing. These are
verified code risks; live failure reproduction remains unavailable because
Computer Use times out on Pulse.

`DashboardFilePicker.swift` now owns a small, testable handoff: request close,
wait for `popoverDidClose`, activate the app, then present and retain a separate
asynchronous `NSOpenPanel`. A repeated request focuses the same panel. After
selection finishes saving, or cancellation, reopen Tasks settings. Cancel keeps
the previous file. Settings reports actual loaded/missing/permission/parse
state and errors rather than calling any stored bookmark “Connected”. Selecting
a file does not implicitly change the user's built-in/Apex source choice; the
settings explain how to display the selected Dashboard on Home.

The new coordinator file isolates AppKit presentation from the existing task
storage/parser and permits simulation without opening panels or changing real
bookmarks. Six tests cover close-completion ordering, repeated requests,
synchronous close callbacks, failure/retry, cancellation and asynchronous save,
including temporary file re-selection and malformed Markdown. The combined
picker/hover run passed all 25 tests. Build and complete regression passed:
**119 tests, 117 passed, 2 existing accessibility tests skipped, 0 failures**.
The native panel's foreground visibility and real mouse interaction still
require desktop verification; simulated panel tests do not establish those.
The new `PulseDashboardPicker` build was launched after stopping the exact
previous process, and its executable was verified. Computer Use again returned
`timeoutReached` for that exact application path. After the panel finishes, the
existing hover policy can dismiss the restored Settings if the pointer remains
outside; check this transition manually and reopen Settings if needed. This
follow-up does not lengthen the departure grace or alter hover suspension.

Manual follow-up: open Settings → Tasks, select Obsidian Dashboard and choose a
test `.md` file. Confirm the independent chooser appears and returns to settings
with a loaded filename. Repeat with another test file, cancel once to confirm
the previous selection stays intact, then check Home's tasks. Invalid Markdown
should show its parse reason in Settings. No private task file needs to be edited
to verify this flow.
