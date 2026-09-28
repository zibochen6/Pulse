import XCTest

@testable import Pulse

@MainActor
final class PopoverHoverControllerTests: XCTestCase {
  func testLeavingBothRegionsClosesAfterDelay() async throws {
    var closeCount = 0
    let pointerInside = false
    let controller = PopoverHoverController(
      delayNanoseconds: 20_000_000,
      isPointerInside: { pointerInside },
      close: { closeCount += 1 }
    )

    controller.synchronize(statusButton: true, content: false)
    controller.exited(.statusButton)
    XCTAssertEqual(closeCount, 0)
    try await Task.sleep(nanoseconds: 40_000_000)
    XCTAssertEqual(closeCount, 1)
  }

  func testReenteringEitherRegionCancelsPendingClose() async throws {
    var closeCount = 0
    let controller = PopoverHoverController(
      delayNanoseconds: 20_000_000,
      isPointerInside: { false },
      close: { closeCount += 1 }
    )

    controller.synchronize(statusButton: true, content: false)
    controller.exited(.statusButton)
    controller.entered(.content)
    try await Task.sleep(nanoseconds: 40_000_000)
    XCTAssertEqual(closeCount, 0)

    controller.exited(.content)
    try await Task.sleep(nanoseconds: 40_000_000)
    XCTAssertEqual(closeCount, 1)
  }

  func testGeometryCheckPreventsCloseAfterStaleExit() async throws {
    var closeCount = 0
    let controller = PopoverHoverController(
      delayNanoseconds: 20_000_000,
      isPointerInside: { true },
      close: { closeCount += 1 }
    )

    controller.synchronize(statusButton: false, content: false)
    try await Task.sleep(nanoseconds: 40_000_000)
    XCTAssertEqual(closeCount, 0)
  }

  func testGeometryCheckRetriesUntilPointerLeaves() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation()
    let controller = PopoverHoverController(
      delayNanoseconds: 20_000_000,
      isPointerInside: { pointer.inside },
      close: { closeCount += 1 }
    )

    controller.synchronize(statusButton: false, content: false)
    try await Task.sleep(nanoseconds: 45_000_000)
    XCTAssertEqual(closeCount, 0)

    pointer.inside = false
    try await Task.sleep(nanoseconds: 45_000_000)
    XCTAssertEqual(closeCount, 1)
  }

  func testResetCancelsCloseAfterSystemDismissal() async throws {
    var closeCount = 0
    let controller = PopoverHoverController(
      delayNanoseconds: 20_000_000,
      isPointerInside: { false },
      close: { closeCount += 1 }
    )

    controller.synchronize(statusButton: false, content: false)
    controller.reset()
    try await Task.sleep(nanoseconds: 40_000_000)
    XCTAssertEqual(closeCount, 0)
  }
}

@MainActor
private final class TestPointerLocation {
  var inside = true
}
