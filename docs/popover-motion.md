# Motion and response

Pulse 0.1.8 uses a fixed 400 × 520 opaque quick panel and
independent Settings. Native NSPopover open/close remains system-owned; there is
no extra whole-panel animation or animated window resizing.

## Motion vocabulary

| Interaction | Target | Character |
| --- | --- | --- |
| Hover | 120 ms | color/opacity ease-out |
| Press | 90 ms | subtle immediate acknowledgement, no bounce |
| Page body | about 200 ms / 8 pt | continuous incoming content and old snapshot fade |
| Tag selection | 180 ms | selected plate follows the chosen tag |
| Composer | 200 ms | expands from Add task, input immediately usable |
| Completion | 180 ms | check and strike-through in place |
| Reorder | 240 ms | slight spring settle at drop location |

All feedback uses shared tokens. A preset's extraBounce of zero is not proof
of zero total bounce: snappy already has baseline bounce. Use explicit
non-bouncy curves for acknowledgement and reserve a mild spring for spatial
movement. Never animate all descendants on arbitrary view updates.

The toolbar remains stable during navigation. The outgoing native field editor
ends before page replacement; an in-memory noninteractive image may fade out,
not the live field. Rapid navigation invalidates the old transition so a stale
snapshot cannot obscure the newest page. Input and save never wait for animation.

Reduce Motion disables native panel motion and removes internal offsets,
scaling and matched-geometry travel, including pressed button scale. A brief
opacity change can still explain a state change. No system accessibility setting
is modified by the app or by automated checks.

## Pointer lifecycle

Opening waits for both its 300 ms minimum guard and native didShow. Departure
from button/content/window starts a single 180 ms grace interval. Re-entry
cancels it; duplicate exits do not extend it. Geometry is rechecked at the
deadline and every 50 ms while shown. Closing cancels timers and ignores late
show/tracking events until native didClose.

Editing, menu tracking and native dragging are independent holding sources.
Menu end releases only that menu. Drop exit changes only the visual marker;
NSDraggingSource end/cancel releases the drag. This preserves the user's
preferred automatic-close behavior without dismissing a menu or drag mid-action.
Outside clicks and explicit status-item toggle still use native semantics.

## Runtime acceptance

Use an isolated development build and sample store:

1. Open the panel and keep the pointer over its status icon for two seconds;
   enter the content and arrow, leave, return within the grace, then leave again.
2. Open a tag ellipsis/context menu beyond the panel and remain there longer
   than 180 ms; select or cancel. A remaining editor still holds the panel.
3. Drag beyond the panel and return; drag to an overflow edge; cancel with
   Escape and release outside. None may leave a dimmed tag or permanent hold.
4. Rapidly switch Home, provider details and tag management. No blank flash,
   stale snapshot, delayed input or accidental task submission is acceptable.
5. Type Chinese with marked-text composition, confirm a candidate, submit,
   switch lists/windows, return and use native Undo/Redo. Verify both the
   displayed string and bound draft.
6. Complete, undo completion, delete/undo and reorder. Rows and delete hit areas
   stay stable; selected tags remain reachable.
7. Inspect light/dark, English/Chinese and injected Reduce Motion variants.
   Native reduced-motion preference is tested only when already set by the user.
8. Confirm real values, error recovery and first-use Connect states remain
   understandable without an explanation.

Unit/render tests are necessary but do not establish live animation or event
quality. The planning baseline passed 79 relevant tests; native Computer Use
access timed out. Final verification results belong in the active task's
verification record and must distinguish completed checks from unavailable ones.
