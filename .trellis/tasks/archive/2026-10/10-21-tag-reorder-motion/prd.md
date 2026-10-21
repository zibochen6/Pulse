# Tag drag reorder and motion polish

## Goal

Let the user arrange the tag tabs by dragging them left and right, and raise the
perceived quality of the task surface by giving every interaction a deliberate,
consistent motion treatment that respects Reduce Motion.

## Requirements

The two user requests driving this change:

1. **The top tag tabs support drag reordering.** A custom tag pill can be
   dragged left or right and dropped where it should live; the order is saved
   and survives relaunch. **Todo** stays fixed at the left and is never
   draggable, because it is a virtual list rather than a stored tag.
2. **Optimize the motion and the UI interaction details; raise the quality.**
   Hover, press, selection, disclosure, insertion and reorder should each have
   one deliberate curve rather than several unrelated durations, controls should
   acknowledge a click physically, keyboard focus should be visible as a
   shape-matched affordance (never a square box), and everything must stay
   silent when the user has asked for Reduce Motion.

## Design decisions

- **Drag technology.** SwiftUI `.onDrag` + `.onDrop(of:delegate:)`, with the
  tag UUID as the pasteboard payload. `DropDelegate.dropUpdated` is the only
  place SwiftUI reports a drag's live position, which is what keeps the
  insertion caret under the pointer instead of answering only at release.
- **Drop geometry is a pure function.** `LocalTagReorder.dropTarget` takes
  measured pill centres and returns the destination index plus the pill/edge
  that draws the caret. It holds no state, so animated layout can never feed
  back into the hit test, and the whole caret rule is unit-testable without a
  view.
- **Centre semantics.** A pill's centre belongs to the gap on its right, so
  moving a tag one place right means pushing it past the *next* tag's centre.
  The dragged tag is excluded when counting the tags that end up before it,
  which is also what bounds the destination to `0..<count`.
- **Storage.** `LocalTaskMutation.moveTag(id:toIndex:)` where `toIndex` is the
  index the tag occupies **after** the move. Out-of-range destinations clamp
  rather than fail (a drag that raced a tag deletion must not become a hard
  error over a drifted count); a tag that no longer exists is `tagMissing`.
  Moving to the tag's own slot is a no-op transaction and writes nothing.
- **Optimistic preview.** The bar renders the dropped order immediately and
  converges when the store's order matches it, or rolls back when the write
  fails. The stored order stays authoritative for drafts, selection, undo and
  filtering.
- **No animated selection fill.** Animating the capsule fill from `.clear` is
  the known way to leave a selected tab blank in off-window renders, so the fill
  stays a discrete state change. Motion lives in press, hover, caret, chevron,
  row and banner transitions instead.
- **Composer removal is instant.** The composer owns a shared AppKit field
  editor; a removal transition that lingers in the tree is exactly how a saved
  draft gets typed back into a field that should be gone. Insertion may glide,
  removal may not.

## Acceptance criteria

- [ ] Drag a custom tab to the far right, to the front, and back; relaunch and
      the order is unchanged. **Todo** never moves.
- [ ] Dropping on **Todo**, on the left half of the first tab, or on the tag's
      own slot changes nothing and shows no caret.
- [ ] While dragging, the dragged tab dims and an accent caret marks the slot
      the tag will land in; the caret reads as a boundary, not as a selection.
- [ ] **Move Left** / **Move Right** from the tab context menu (⌥⌘← / ⌥⌘→) and
      from Settings → Tasks land the tag in the same slot as the equivalent
      drag.
- [ ] Every new animation is gated on Reduce Motion; with it on, no hover,
      press, disclosure, row or drag feedback animates and behavior is unchanged.
- [ ] Keyboard focus on a tab shows the shape-matched capsule affordance, not a
      square box; press gives a scale-down acknowledgement.
- [ ] `schemaVersion` stays 1; a move never changes task identity, stored task
      order, text, completion, repeat state or tag names.
- [ ] The whole existing suite stays green and the new pure-geometry, storage,
      controller and presentation cases pass.

## Out of scope

- Task row reordering (only tags).
- Release, local install or a GitHub push; this change is code, tests and docs.
- Any third-party dependency, including Sparkle.
