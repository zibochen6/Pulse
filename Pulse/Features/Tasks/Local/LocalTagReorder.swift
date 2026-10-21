import CoreGraphics
import Foundation

/// Which edge of a tag pill the insertion caret is drawn on while a tag is
/// being dragged over it. The caret sits half outside the capsule, so it reads
/// as the boundary between two pills rather than as another selected tab.
enum LocalTagDropEdge: Equatable, Sendable {
  case leading
  case trailing
}

/// The pill that would receive the drop, where the caret draws on it, and the
/// final index the dragged tag would occupy after the move.
struct LocalTagDropTarget: Equatable, Sendable {
  /// The tag pill that shows the insertion caret.
  let pillID: UUID
  /// Destination index of the dragged tag in the tag array *after* the move.
  /// This is exactly the `toIndex` of `LocalTaskMutation.moveTag`.
  let index: Int
  let edge: LocalTagDropEdge

  init(pillID: UUID, index: Int, edge: LocalTagDropEdge) {
    self.pillID = pillID
    self.index = index
    self.edge = edge
  }
}

/// Pure drop geometry for the tag bar. The bar renders one fixed **Todo** pill
/// followed by the custom tags in stored order, so only the custom tags have a
/// movable position and Todo is always the left boundary.
///
/// A pill's centre belongs to the gap on its right: moving a tag one place to
/// the right means pushing it past the *next* tag's centre, never past its own.
/// The dragged tag is therefore excluded when counting the tags that end up
/// before it, which is also what bounds the result to `0..<tagIDs.count`.
///
/// This deliberately computes no state of its own, so the drag surface only has
/// to supply measured pill centres and can never feed animated layout back into
/// the hit test.
enum LocalTagReorder {

  /// Where a drop of `draggedID` at `locationX` would land, or `nil` when the
  /// drop is ignored: left of the fixed Todo tab, on the tag's own current
  /// slot, on a tag that is not part of `tagIDs`, or before every pill has been
  /// measured.
  ///
  /// - Parameters:
  ///   - draggedID: The tag currently being dragged.
  ///   - locationX: Pointer x in the same coordinate space as `midXByID`.
  ///   - tagIDs: Custom tag IDs in currently displayed order.
  ///   - todoMidX: Centre of the fixed Todo pill; drops left of it are ignored.
  ///   - midXByID: Measured centre of each custom tag pill.
  static func dropTarget(
    draggedID: UUID,
    locationX: CGFloat,
    tagIDs: [UUID],
    todoMidX: CGFloat,
    midXByID: [UUID: CGFloat]
  ) -> LocalTagDropTarget? {
    // Todo owns everything left of its centre: a tag can never precede it.
    guard locationX >= todoMidX else { return nil }
    guard let from = tagIDs.firstIndex(of: draggedID) else { return nil }
    // Without a complete measurement the computed boundary would be a guess.
    guard tagIDs.allSatisfy({ midXByID[$0] != nil }) else { return nil }

    // The dragged tag's own slot is not an obstacle on its way somewhere else,
    // so only the remaining tags are counted. At most `count - 1` remain, which
    // keeps the destination inside the array without clamping.
    let passed = tagIDs.filter {
      $0 != draggedID && (midXByID[$0] ?? .greatestFiniteMagnitude) <= locationX
    }.count
    guard passed != from else { return nil }

    // Moving right leaves the tag after its old neighbour, so the caret belongs
    // on the destination pill's trailing edge; moving left means it arrives in
    // front of that pill instead.
    let edge: LocalTagDropEdge = passed > from ? .trailing : .leading
    return LocalTagDropTarget(pillID: tagIDs[passed], index: passed, edge: edge)
  }
}
