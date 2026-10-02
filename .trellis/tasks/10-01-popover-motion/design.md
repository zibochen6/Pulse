# Design

## Boundary
Only AppKit presentation and PopoverHoverController change. Views and provider/task data layers remain untouched. Existing opaque Home background stays in place.

## Lifecycle
Opening requires both the 300 ms guard and popoverDidShow. Hover state gains Closing so cancellation and request gating stay testable in one controller. popoverWillClose cancels all work even for native outside clicks; popoverDidClose resets controller and navigation. Ignored close/open requests during Closing avoid overlapping native animations.

## Pointer timing
Keep tracking plus 50 ms actual geometry reconciliation. Track the entire window, including its arrow. PendingClose is scheduled once; re-entry cancels it. At 180 ms reread actual pointer geometry and close only when outside. Editing suppresses only hover close.

## Motion and accessibility
Use NSPopover.animates with the current NSWorkspace Reduce Motion setting, refreshed on presentation and close and on accessibility display changes. macOS owns animation duration/effect. Do not animate window size, install snapshots, or introduce custom panels.

## Compatibility
No defaults migration or data change. Existing uncommitted built-in task work remains intact. A running binary must be restarted after rebuilding.

## Dashboard picker handoff
Extract a small AppKit picker coordinator so the native modal interaction can
be simulated in tests. Request popover close first and present the independent
asynchronous panel only after didClose. Activate the accessory app and bring
the picker forward; repeated requests focus the same panel. Selection saves
through the existing task controller, then restores Settings/Tasks with real
state feedback. Cancellation leaves bookmark/source untouched. Source choice
does not change implicitly. No parser or storage transaction changes.
