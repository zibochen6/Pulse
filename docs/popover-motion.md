# Popover motion and response

## Behavior

Pulse keeps the 360×380 task-first layout and opaque adaptive background. The
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

## In-panel motion

Everything inside the panel draws from `PulseDesignTokens`, so hover, selection,
page entry and completion read as one system. Durations sit in the
90–260 ms band and every spring is either critically damped or very slightly
overshooting.

| Token | Value | Used by |
| --- | --- | --- |
| `hoverAnimation` | snappy 120 ms, no bounce | hover and keyboard-focus fills |
| `pressAnimation` | snappy 90 ms, no bounce | pointer-down feedback |
| `selectionAnimation` | snappy 200 ms, bounce 0.06 | checkbox fill and checkmark |
| `tabSwitchAnimation` | snappy 180 ms, bounce 0.04 | tag selection plate and list refresh |
| `composerAnimation` | snappy 200 ms, no bounce | quick-entry expand and collapse |
| `pageTransitionAnimation` | snappy 180 ms, no bounce | Home / Usage / Settings entry |
| `completionAnimation` | snappy 200 ms, bounce 0.04 | pending save and list membership |
| `reorderAnimation` | snappy 260 ms, bounce 0.12 | tag drag settle |
| `insertionAnimation` | snappy 180 ms, no bounce | update banner insertion |

Rules that keep those transitions honest:

- Animation is scoped with `.animation(_:value:)` on the smallest state that
  changed, never on the root view, so a transition can be interrupted and never
  delays typing or saving.
- Page entry moves a few points in the direction of travel and fades in; the
  outgoing page keeps identity, because a removed page must not carry the shared
  field editor with it.
- A task finishing is one continuous move: the press feedback, the save result
  and the checkmark share a single scoped animation, and the pending spinner
  never changes the row's geometry. The row itself does not travel — it stays
  in place and only strikes through.
- Reduce Motion drops offsets, springs and scale, leaving plain opacity, and the
  tag selection plate is not installed at all.
- Popover open/close stays native and system-owned.

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

The current build and full regression run passed: **209 tests, 0 failures**
(an earlier hover pass ran 113 with 2 skips). The directed hover suite passed all
19 tests. Strict Swift formatting and `git diff --check` passed.
Unit tests cover timing, cancellation, missing events, repeated exits, arrow geometry,
edit suspension, immediate close, stale callbacks and closing reset. A native
NSPopover integration test checks actual didShow/willClose/didClose callbacks
with animation enabled and disabled. It passed in the final run; intermediate
attempts while the graphical session was locked failed to receive didShow. The
test now explicitly skips locked/non-console sessions and allows a longer wait
for system-owned animation callbacks, without changing application timing.
Existing rendering tests passed for Aqua/Dark Aqua and opaque edges with
fictional data; their generated Home images were inspected. The layout and
motion pass added checks that the fixed 360×380 surface never changes ratio,
that the quota strip
lays out below the toolbar, that the task list fits the height the popover
actually leaves it, that a pending completion does not move its row, and that the
tag selection plate is really painted in an off-window render.

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
2. Move into the popover and switch a tag tab or Settings. It stays open.
3. Leave both regions; after a short grace, native dismissal should be visible.
   Return within the grace and confirm dismissal is cancelled.
4. Repeatedly click the status item: a closing animation should finish without
   reopening or flashing. The next deliberate click opens Home.
5. Open a task editor. Departure alone should keep the draft open; an outside
   click may dismiss it. Reopening should retain the existing draft behavior.
6. With the user's Reduce Motion preference enabled, opening/closing should
   have no motion. Do not change accessibility settings during automated tests.
7. Switch a tag tab: the accent plate slides between pills rather than fading,
   the list refresh is a light update, and rapid tab switching settles on the
   tab actually clicked.
8. Type in quick entry, then press Return: press feedback, save and checkmark
   read as one motion with no row jumping sideways, and the finished task stays
   in its own place rather than moving somewhere else.
9. Move between Home, Usage and Settings: each destination enters with a small
   move plus fade in its own direction, returning Home comes back the other way,
   and a half-finished animation never blocks typing. With Reduce Motion these
   become plain cross-fades with no offset.

No task data or quota fetching is changed by this update; the layout, typography
and in-panel motion changes described above do apply to it.
An earlier follow-up about a Settings file-chooser handoff belonged to the task
integration that has since been removed; the task surface is now the native
local list only, so that handoff and its manual checks no longer apply.
