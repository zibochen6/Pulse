import Foundation
import XCTest

@testable import Pulse

@MainActor
final class PopoverInteractionHoldsTests: XCTestCase {
  func testMenuAndDragEndDoNotReleaseAnActiveEditor() {
    let holds = PopoverInteractionHolds()
    let menu = NSObject()
    var changes: [Bool] = []
    holds.onChange = { changes.append($0) }
    holds.set(.taskEditor, active: true)
    let menuLease = holds.begin(.menu(ObjectIdentifier(menu)))
    let dragLease = holds.begin(.drag(UUID()))
    holds.end(menuLease)
    holds.end(dragLease)
    XCTAssertTrue(holds.isActive)
    XCTAssertEqual(changes, [true])
    holds.set(.taskEditor, active: false)
    XCTAssertEqual(changes, [true, false])
  }

  func testNestedMenusAndRepeatedEditorUpdatesAreIndependent() {
    let holds = PopoverInteractionHolds()
    let parent = NSObject()
    let child = NSObject()
    holds.set(.taskEditor, active: true)
    holds.set(.taskEditor, active: true)
    let parentLease = holds.begin(.menu(ObjectIdentifier(parent)))
    let childLease = holds.begin(.menu(ObjectIdentifier(child)))
    holds.end(parentLease)
    holds.set(.taskEditor, active: false)
    XCTAssertTrue(holds.isActive)
    holds.end(childLease)
    XCTAssertFalse(holds.isActive)
  }

  func testLateCancellationCannotReleaseReopenedSession() {
    let holds = PopoverInteractionHolds()
    let source = PopoverInteractionHolds.Source.drag(UUID())
    let old = holds.begin(source)
    holds.reset()
    let current = holds.begin(source)
    holds.end(old)
    XCTAssertTrue(holds.isActive)
    holds.end(current)
    XCTAssertFalse(holds.isActive)
  }

  func testReplacingSessionAndResetReleaseOnlyCurrentHoldOnce() {
    let holds = PopoverInteractionHolds()
    var changes: [Bool] = []
    holds.onChange = { changes.append($0) }
    let old = holds.begin(.tagChooser)
    _ = holds.begin(.tagChooser)
    holds.end(old)
    XCTAssertTrue(holds.isActive)
    holds.reset()
    holds.reset()
    XCTAssertEqual(changes, [true, false])
  }
}
