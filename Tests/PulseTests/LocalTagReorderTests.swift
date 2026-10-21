import XCTest

@testable import Pulse

final class LocalTagReorderTests: XCTestCase {
  private let todo = UUID()
  private let a = UUID()
  private let b = UUID()
  private let c = UUID()

  /// Pills sit on centres 10 / 30 / 50 with the fixed Todo tab at 0, so the
  /// custom tags render in the order A, B, C. Every case below reads the
  /// pointer against that layout.
  private var mids: [UUID: CGFloat] { [a: 10, b: 30, c: 50] }

  private func target(_ x: CGFloat, dragging: UUID, ids: [UUID]? = nil) -> LocalTagDropTarget? {
    LocalTagReorder.dropTarget(
      draggedID: dragging, locationX: x, tagIDs: ids ?? [a, b, c], todoMidX: 0, midXByID: mids)
  }

  // MARK: - Placement

  func testMovingRightLandsAfterThePassedNeighbour() throws {
    // Pointer past B's centre: A arrives between B and C.
    let drop = try XCTUnwrap(target(45, dragging: a))
    XCTAssertEqual(drop.pillID, b)
    XCTAssertEqual(drop.index, 1)
    XCTAssertEqual(drop.edge, .trailing)
  }

  func testPointerPastEveryPillMovesToTheEnd() throws {
    let drop = try XCTUnwrap(target(500, dragging: a))
    XCTAssertEqual(drop.pillID, c)
    XCTAssertEqual(drop.index, 2)
    XCTAssertEqual(drop.edge, .trailing)
  }

  func testMovingLeftLandsBeforeTheDestinationPill() throws {
    // Pointer between A and B: C arrives between A and B.
    let drop = try XCTUnwrap(target(15, dragging: c))
    XCTAssertEqual(drop.pillID, b)
    XCTAssertEqual(drop.index, 1)
    XCTAssertEqual(drop.edge, .leading)
  }

  func testPointerBetweenTodoAndFirstTagMovesToTheFront() throws {
    let drop = try XCTUnwrap(target(5, dragging: c))
    XCTAssertEqual(drop.pillID, a)
    XCTAssertEqual(drop.index, 0)
    XCTAssertEqual(drop.edge, .leading)
    let middle = try XCTUnwrap(target(5, dragging: b))
    XCTAssertEqual(middle.index, 0)
    XCTAssertEqual(middle.edge, .leading)
    XCTAssertEqual(middle.pillID, a)
  }

  // MARK: - Ignored drops

  func testDroppingOnItsOwnSlotIsIgnored() {
    XCTAssertNil(target(5, dragging: a), "A is already first")
    XCTAssertNil(target(15, dragging: a), "gap after A is A's own slot")
    XCTAssertNil(target(15, dragging: b), "gap after A is B's own slot")
    XCTAssertNil(target(25, dragging: b), "left half of B is still B's slot")
    XCTAssertNil(target(30, dragging: b), "B's own centre is its own slot")
    XCTAssertNil(target(45, dragging: c), "gap after B is C's own slot")
    XCTAssertNil(target(55, dragging: c), "C is already last")
  }

  func testATagOnlyMovesRightOnceItPassesTheNextCentre() {
    // Dragging B rightward stays put until the pointer is past C's centre.
    XCTAssertNil(target(31, dragging: b))
    XCTAssertNil(target(49, dragging: b))
    let drop = target(51, dragging: b)
    XCTAssertEqual(drop?.index, 2)
    XCTAssertEqual(drop?.edge, .trailing)
    XCTAssertEqual(drop?.pillID, c)
  }

  func testDropsLeftOfTodoAreIgnored() {
    XCTAssertNil(
      LocalTagReorder.dropTarget(
        draggedID: c, locationX: -20, tagIDs: [a, b, c], todoMidX: 0, midXByID: mids))
    XCTAssertNil(
      LocalTagReorder.dropTarget(
        draggedID: a, locationX: -0.5, tagIDs: [a, b, c], todoMidX: 0, midXByID: mids))
  }

  func testASingleTagNeverMoves() {
    XCTAssertNil(target(5, dragging: a, ids: [a]))
    XCTAssertNil(target(10, dragging: a, ids: [a]))
    XCTAssertNil(target(500, dragging: a, ids: [a]))
  }

  func testUnknownDraggedTagIsIgnored() {
    XCTAssertNil(target(45, dragging: UUID()))
    XCTAssertNil(target(45, dragging: a, ids: []))
  }

  func testUnmeasuredPillsAreNeverGuessed() {
    XCTAssertNil(
      LocalTagReorder.dropTarget(
        draggedID: a, locationX: 45, tagIDs: [a, b, c], todoMidX: 0,
        midXByID: [a: 10, b: 30]))
  }

  // MARK: - Boundary determinism

  func testAPillCentreBelongsToTheGapOnItsRight() throws {
    // Exactly on B's centre while dragging A: B counts as passed.
    let right = try XCTUnwrap(target(30, dragging: a))
    XCTAssertEqual(right.pillID, b)
    XCTAssertEqual(right.index, 1)
    XCTAssertEqual(right.edge, .trailing)
    // Exactly on B's centre while dragging B: still B's own slot.
    XCTAssertNil(target(30, dragging: b))
    // Exactly on B's centre while dragging C: already last after B.
    XCTAssertNil(target(30, dragging: c))
  }

  // MARK: - Result is directly usable as the store's toIndex

  func testReportedIndexIsTheIndexAfterTheMove() throws {
    // [A, B, C] -> move A after B -> [B, A, C]: A ends at index 1.
    XCTAssertEqual(try XCTUnwrap(target(45, dragging: a)).index, 1)
    // [A, B, C] -> move C before A -> [C, A, B]: C ends at index 0.
    XCTAssertEqual(try XCTUnwrap(target(5, dragging: c)).index, 0)
    // [A, B, C] -> move B to the end -> [A, C, B]: B ends at index 2.
    XCTAssertEqual(try XCTUnwrap(target(500, dragging: b)).index, 2)
  }
}
