import XCTest

@testable import Pulse

@MainActor
final class PopoverHoverControllerTests: XCTestCase {
  private let openingDelay: UInt64 = 100_000_000
  private let closeDelay: UInt64 = 80_000_000

  func testOpeningIgnoresExitAndRereadsPointerGeometry() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation(statusButton: true)
    let controller = makeController(pointer: pointer) { closeCount += 1 }

    controller.beginOpening()
    controller.synchronize(statusButton: true, content: false)
    // The click can produce a stale exit event.
    controller.exited(.statusButton)
    XCTAssertEqual(controller.state, .opening)
    try await Task.sleep(nanoseconds: 25_000_000)
    XCTAssertEqual(closeCount, 0)

    try await waitForState(.interactive, on: controller)
    XCTAssertEqual(controller.state, .interactive)
    XCTAssertEqual(closeCount, 0)
    // The pointer can remain at the clicked button for longer than both delays.
    try await Task.sleep(nanoseconds: 190_000_000)
    XCTAssertEqual(closeCount, 0)
  }

  func testOpeningWithPointerOutsideTransitionsToPendingClose() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation()
    let controller = makeController(pointer: pointer) { closeCount += 1 }

    controller.beginOpening()
    controller.synchronize(statusButton: true, content: false)
    controller.exited(.statusButton)
    try await waitForState(.pendingClose, on: controller)
    XCTAssertEqual(controller.state, .pendingClose)
    XCTAssertEqual(closeCount, 0)

    try await waitForState(.closed, on: controller)
    XCTAssertEqual(closeCount, 1)
    XCTAssertEqual(controller.state, .closed)
  }

  func testReenteringEitherRegionCancelsPendingClose() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation()
    let controller = makeController(pointer: pointer) { closeCount += 1 }
    controller.beginOpening()
    try await waitForState(.pendingClose, on: controller)
    XCTAssertEqual(controller.state, .pendingClose)

    pointer.content = true
    controller.entered(.content)
    XCTAssertEqual(controller.state, .interactive)
    try await Task.sleep(nanoseconds: 110_000_000)
    XCTAssertEqual(closeCount, 0)

    pointer.statusButton = false
    pointer.content = false
    controller.exited(.content)
    XCTAssertEqual(controller.state, .pendingClose)
    try await waitForState(.closed, on: controller)
    XCTAssertEqual(closeCount, 1)
  }

  func testGeometryRetryCoversPopoverArrowWithoutTrackedEntry() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation(popoverWindow: true)
    let controller = makeController(pointer: pointer) { closeCount += 1 }
    controller.beginOpening()
    try await waitForState(.pendingClose, on: controller)
    try await Task.sleep(nanoseconds: 110_000_000)
    XCTAssertEqual(controller.state, .pendingClose)
    XCTAssertEqual(closeCount, 0)

    pointer.popoverWindow = false
    try await waitForState(.closed, on: controller)
    XCTAssertEqual(closeCount, 1)
  }

  func testResetCancelsOpeningAndPendingWork() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation()
    let controller = makeController(pointer: pointer) { closeCount += 1 }

    controller.beginOpening()
    // AppKit can close the transient popover during Opening.
    controller.reset()
    try await Task.sleep(nanoseconds: 130_000_000)
    XCTAssertEqual(controller.state, .closed)
    XCTAssertEqual(closeCount, 0)

    controller.beginOpening()
    try await waitForState(.pendingClose, on: controller)
    XCTAssertEqual(controller.state, .pendingClose)
    controller.reset()
    try await Task.sleep(nanoseconds: 110_000_000)
    XCTAssertEqual(controller.state, .closed)
    XCTAssertEqual(closeCount, 0)
  }

  func testSecondOpeningReplacesPreviousOpeningTask() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation(statusButton: true)
    let controller = makeController(pointer: pointer, openingDelay: 600_000_000) {
      closeCount += 1
    }

    controller.beginOpening()
    try await Task.sleep(nanoseconds: 250_000_000)
    controller.beginOpening()
    // Pass the first task's deadline while leaving a wider margin before the
    // replacement task's deadline, so scheduling noise does not decide this test.
    try await Task.sleep(nanoseconds: 400_000_000)
    XCTAssertEqual(controller.state, .opening)
    try await waitForState(.interactive, on: controller)
    XCTAssertEqual(controller.state, .interactive)
    XCTAssertEqual(closeCount, 0)
  }

  private func makeController(
    pointer: TestPointerLocation,
    openingDelay: UInt64? = nil,
    close: @escaping @MainActor () -> Void
  ) -> PopoverHoverController {
    PopoverHoverController(
      openingNanoseconds: openingDelay ?? self.openingDelay,
      closeDelayNanoseconds: closeDelay,
      pointerPresence: { pointer.presence },
      close: close
    )
  }

  private func waitForState(
    _ expected: PopoverHoverState,
    on controller: PopoverHoverController
  ) async throws {
    for _ in 0..<100 {
      if controller.state == expected { return }
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("Timed out waiting for \(expected); current state is \(controller.state)")
  }
}

@MainActor
private final class TestPointerLocation {
  var statusButton: Bool
  var content: Bool
  var popoverWindow: Bool

  init(statusButton: Bool = false, content: Bool = false, popoverWindow: Bool = false) {
    self.statusButton = statusButton
    self.content = content
    self.popoverWindow = popoverWindow
  }

  var presence: PopoverPointerPresence {
    PopoverPointerPresence(
      statusButton: statusButton, content: content, popoverWindow: popoverWindow)
  }
}
