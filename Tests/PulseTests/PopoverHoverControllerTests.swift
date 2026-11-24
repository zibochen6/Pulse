import AppKit
import CoreGraphics
import XCTest

@testable import Pulse

@MainActor
final class PopoverHoverControllerTests: XCTestCase {
  private let openingDelay: UInt64 = 100_000_000
  private let closeDelay: UInt64 = 80_000_000

  func testPanelHoverCoversItsFullWidthThroughTheMenuBar() {
    // A secondary display with a nonzero origin and a gap above the popover.
    let screen = NSRect(x: -1_440, y: 100, width: 1_440, height: 900)
    let panel = NSRect(x: -650, y: 440, width: 400, height: 520)

    func keepsOpen(_ x: CGFloat, _ y: CGFloat) -> Bool {
      PopoverPointerPresence.coversPopover(
        NSPoint(x: x, y: y), frame: panel, screen: screen)
    }

    XCTAssertTrue(keepsOpen(-450, 978))  // Gap between the panel and menu bar.
    XCTAssertTrue(keepsOpen(-450, 1_000))  // Top pixel of the display.
    XCTAssertTrue(keepsOpen(-649, 999))  // Above the left side of the panel.
    XCTAssertTrue(keepsOpen(-251, 999))  // Above the right side of the panel.
    XCTAssertTrue(keepsOpen(-450, 441))
    XCTAssertFalse(keepsOpen(-651, 990))
    XCTAssertFalse(keepsOpen(-249, 990))
    XCTAssertFalse(keepsOpen(-450, 439))
    XCTAssertFalse(keepsOpen(-450, 1_001))
    XCTAssertFalse(
      PopoverPointerPresence.coversPopover(NSPoint(x: -450, y: 999), frame: panel, screen: nil))
  }

  func testOpeningIgnoresExitAndRereadsPointerGeometry() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation(statusButton: true)
    let controller = makeController(pointer: pointer) { closeCount += 1 }

    controller.beginOpening()
    controller.presentationDidShow()
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
    controller.presentationDidShow()
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
    controller.presentationDidShow()
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

  func testGeometryTracksPopoverArrowWithoutContentEntry() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation(popoverWindow: true)
    let controller = makeController(pointer: pointer) { closeCount += 1 }
    controller.beginOpening()
    controller.presentationDidShow()
    try await waitForState(.interactive, on: controller)
    try await Task.sleep(nanoseconds: 110_000_000)
    XCTAssertEqual(controller.state, .interactive)
    XCTAssertEqual(closeCount, 0)

    pointer.popoverWindow = false
    try await waitForState(.closed, on: controller)
    XCTAssertEqual(closeCount, 1)
  }

  func testInteractiveReconcilesMissedExitBeforeClosing() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation(statusButton: true)
    let controller = makeController(pointer: pointer) { closeCount += 1 }

    controller.beginOpening()
    controller.presentationDidShow()
    try await waitForState(.interactive, on: controller)
    XCTAssertEqual(controller.state, .interactive)

    // Simulate AppKit missing mouseExited while the SwiftUI content changes.
    pointer.statusButton = false
    try await waitForState(.pendingClose, on: controller)
    try await waitForState(.closed, on: controller)
    XCTAssertEqual(closeCount, 1)
  }

  func testInteractiveReconcilesMissedEntryAndCancelsPendingClose() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation()
    let controller = makeController(pointer: pointer) { closeCount += 1 }

    controller.beginOpening()
    controller.presentationDidShow()
    try await waitForState(.pendingClose, on: controller)

    // Simulate AppKit missing mouseEntered after the pointer returns to content.
    pointer.content = true
    try await waitForState(.interactive, on: controller)
    try await Task.sleep(nanoseconds: 110_000_000)
    XCTAssertEqual(closeCount, 0)

    pointer.content = false
    try await waitForState(.closed, on: controller)
    XCTAssertEqual(closeCount, 1)
  }

  func testResetCancelsOpeningAndPendingWork() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation()
    let controller = makeController(pointer: pointer) { closeCount += 1 }

    controller.beginOpening()
    controller.presentationDidShow()
    // AppKit can close the transient popover during Opening.
    controller.reset()
    try await Task.sleep(nanoseconds: 130_000_000)
    XCTAssertEqual(controller.state, .closed)
    XCTAssertEqual(closeCount, 0)

    controller.beginOpening()
    controller.presentationDidShow()
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
    controller.presentationDidShow()
    try await Task.sleep(nanoseconds: 250_000_000)
    controller.beginOpening()
    controller.presentationDidShow()
    // Pass the first task's deadline while leaving a wider margin before the
    // replacement task's deadline, so scheduling noise does not decide this test.
    try await Task.sleep(nanoseconds: 400_000_000)
    XCTAssertEqual(controller.state, .opening)
    try await waitForState(.interactive, on: controller)
    XCTAssertEqual(controller.state, .interactive)
    XCTAssertEqual(closeCount, 0)
  }

  func testEditingSuspendsPendingCloseAndResumesDepartureDelay() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation()
    let controller = makeController(pointer: pointer) { closeCount += 1 }
    controller.beginOpening()
    controller.presentationDidShow()
    try await waitForState(.pendingClose, on: controller)
    controller.setDismissalSuspended(true)
    XCTAssertEqual(controller.state, .interactive)
    try await Task.sleep(nanoseconds: 140_000_000)
    XCTAssertEqual(closeCount, 0)
    controller.setDismissalSuspended(false)
    XCTAssertEqual(controller.state, .pendingClose)
    try await waitForState(.closed, on: controller)
    XCTAssertEqual(closeCount, 1)
  }

  func testEditingDuringOpeningAndSystemCloseResetsSuspension() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation()
    let controller = makeController(pointer: pointer) { closeCount += 1 }
    controller.beginOpening()
    controller.presentationDidShow()
    controller.setDismissalSuspended(true)
    try await waitForState(.interactive, on: controller)
    try await Task.sleep(nanoseconds: 140_000_000)
    XCTAssertEqual(closeCount, 0)
    // A native outside click still invokes reset even while editing.
    controller.reset()
    controller.beginOpening()
    controller.presentationDidShow()
    try await waitForState(.closed, on: controller)
    XCTAssertEqual(closeCount, 1)
  }

  func testHoverHoldStopsReconciliationAndSamplesOnceOnRelease() async throws {
    var samples = 0
    let controller = PopoverHoverController(
      openingNanoseconds: openingDelay,
      closeDelayNanoseconds: closeDelay,
      reconciliationNanoseconds: 10_000_000,
      pointerPresence: {
        samples += 1
        return PopoverPointerPresence(statusButton: false, content: false, popoverWindow: false)
      },
      close: {}
    )
    defer { controller.reset() }
    controller.beginOpening()
    controller.setDismissalSuspended(true)
    controller.presentationDidShow()
    try await waitForState(.interactive, on: controller)
    controller.exited(.statusButton)
    try await Task.sleep(for: .milliseconds(60))
    XCTAssertEqual(samples, 0)

    controller.setDismissalSuspended(false)
    XCTAssertEqual(samples, 1)
    XCTAssertEqual(controller.state, .pendingClose)
  }

  func testStatusReopenPreservesClickParityThroughNativeClose() {
    var intent = PopoverReopenIntent()
    intent.toggle(from: .pointer)
    XCTAssertNil(intent.consumeScheduledOpen())
    intent.toggle(from: .keyboard)
    XCTAssertFalse(intent.scheduleAfterClose())

    intent.toggle(from: .keyboard)
    XCTAssertTrue(intent.scheduleAfterClose())
    XCTAssertFalse(intent.scheduleAfterClose(), "Only one open is scheduled")
    intent.toggle(from: .pointer)
    intent.toggle(from: .keyboard)
    XCTAssertEqual(intent.consumeScheduledOpen(), .keyboard)
    XCTAssertFalse(intent.isScheduled)
    XCTAssertNil(intent.consumeScheduledOpen())
  }

  func testSettingsAndExitCanClearScheduledPopoverOpen() {
    var intent = PopoverReopenIntent()
    intent.request(from: .keyboard)
    XCTAssertTrue(intent.scheduleAfterClose())
    intent.clear()
    XCTAssertNil(intent.consumeScheduledOpen())
    XCTAssertFalse(intent.isScheduled)
  }

  func testProtectionExpiryWaitsForNativePresentationCompletion() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation()
    let controller = makeController(pointer: pointer) { closeCount += 1 }
    controller.beginOpening()
    controller.exited(.statusButton)
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertEqual(controller.state, .opening)
    XCTAssertEqual(closeCount, 0)

    controller.presentationDidShow()
    XCTAssertEqual(controller.state, .pendingClose)
    try await waitForState(.closed, on: controller)
    XCTAssertEqual(closeCount, 1)
  }

  func testPresentationCompletionDoesNotSkipClickProtection() async throws {
    var closeCount = 0
    let controller = makeController(pointer: TestPointerLocation()) { closeCount += 1 }
    controller.beginOpening()
    controller.presentationDidShow()
    try await Task.sleep(nanoseconds: 25_000_000)
    XCTAssertEqual(controller.state, .opening)
    XCTAssertEqual(closeCount, 0)
    try await waitForState(.closed, on: controller)
    XCTAssertEqual(closeCount, 1)
  }

  func testDuplicateExitsDoNotExtendPendingDeadline() async throws {
    var closeCount = 0
    let controller = makeController(pointer: TestPointerLocation()) { closeCount += 1 }
    controller.beginOpening()
    controller.presentationDidShow()
    try await waitForState(.pendingClose, on: controller)

    // Repeated exits would postpone closure forever if each replaces the timer.
    for _ in 0..<8 {
      controller.exited(.content)
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertEqual(closeCount, 1)
    XCTAssertEqual(controller.state, .closed)
  }

  func testWindowOnlyReentryCancelsPendingClose() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation()
    let controller = makeController(pointer: pointer) { closeCount += 1 }
    controller.beginOpening()
    controller.presentationDidShow()
    try await waitForState(.pendingClose, on: controller)

    pointer.popoverWindow = true
    try await waitForState(.interactive, on: controller)
    try await Task.sleep(nanoseconds: 110_000_000)
    XCTAssertEqual(closeCount, 0)
    pointer.popoverWindow = false
    try await waitForState(.closed, on: controller)
    XCTAssertEqual(closeCount, 1)
  }

  func testNativeCloseCancelsProtectionAndIgnoresLateEvents() async throws {
    var closeCount = 0
    let controller = makeController(pointer: TestPointerLocation()) { closeCount += 1 }
    controller.beginOpening()
    controller.beginClosing()
    controller.presentationDidShow()
    controller.entered(.content)
    controller.exited(.statusButton)
    controller.synchronize(statusButton: false, content: false)
    controller.setDismissalSuspended(true)
    controller.beginOpening()
    controller.requestClose()
    try await Task.sleep(nanoseconds: 220_000_000)
    XCTAssertEqual(controller.state, .closing)
    XCTAssertEqual(closeCount, 0)

    controller.reset()
    controller.beginOpening()
    controller.presentationDidShow()
    try await waitForState(.closed, on: controller)
    XCTAssertEqual(closeCount, 1)
  }

  func testNativeCloseCancelsPendingWork() async throws {
    var closeCount = 0
    let controller = makeController(pointer: TestPointerLocation()) { closeCount += 1 }
    controller.beginOpening()
    controller.presentationDidShow()
    try await waitForState(.pendingClose, on: controller)
    controller.beginClosing()
    try await Task.sleep(nanoseconds: 140_000_000)
    XCTAssertEqual(closeCount, 0)
    XCTAssertEqual(controller.state, .closing)
    controller.reset()
    XCTAssertEqual(controller.state, .closed)
  }

  func testExplicitCloseIsImmediateAndCannotReopenDuringDismissal() async throws {
    var closeCount = 0
    let pointer = TestPointerLocation(statusButton: true)
    let controller = makeController(pointer: pointer, completesClosing: false) { closeCount += 1 }
    controller.beginOpening()
    // A second click closes even before the native show animation completes.
    controller.requestClose()
    XCTAssertEqual(closeCount, 1)
    XCTAssertEqual(controller.state, .closing)
    controller.requestClose()
    controller.beginOpening()
    controller.entered(.content)
    controller.presentationDidShow()
    try await Task.sleep(nanoseconds: 220_000_000)
    XCTAssertEqual(closeCount, 1)
    XCTAssertEqual(controller.state, .closing)

    controller.reset()
    controller.beginOpening()
    controller.presentationDidShow()
    try await waitForState(.interactive, on: controller)
    XCTAssertEqual(closeCount, 1)
    controller.reset()
  }

  func testDefaultDepartureDelayClosesSoonerThanFormerDelay() async throws {
    let pointer = TestPointerLocation(statusButton: true)
    var closeCount = 0
    let controller = PopoverHoverController(
      openingNanoseconds: 1_000_000,
      pointerPresence: { pointer.presence }, close: { closeCount += 1 })
    controller.beginOpening()
    controller.presentationDidShow()
    try await waitForState(.interactive, on: controller)
    pointer.statusButton = false
    let started = ContinuousClock.now
    controller.exited(.statusButton)
    try await waitForState(.closing, on: controller)
    let elapsed = started.duration(to: .now)
    XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(150))
    XCTAssertLessThan(elapsed, .milliseconds(350))
    XCTAssertEqual(closeCount, 1)
    controller.reset()
  }

  func testNativePresentationCallbacksWithAndWithoutAnimation() async throws {
    // This session dictionary check is test-only. A locked WindowServer does
    // not complete visible popover animation; do not misreport UI acceptance.
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    try XCTSkipIf(
      session?[kCGSessionOnConsoleKey as String] as? Bool != true
        || session?["CGSSessionScreenIsLocked"] as? Bool == true,
      "Native popover animation requires an unlocked graphical session; state-machine tests remain available."
    )
    // Check AppKit's actual completion callbacks, including the no-motion path.
    // This is not a mouse interaction or visual acceptance test.
    for animates in [false, true] {
      let window = NSWindow(
        contentRect: NSRect(x: 200, y: 200, width: 100, height: 100),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
      window.contentView = anchor
      let popover = NSPopover()
      popover.animates = animates
      let content = NSViewController()
      content.view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
      popover.contentViewController = content
      let controller = PopoverHoverController(
        openingNanoseconds: 1_000_000,
        pointerPresence: {
          PopoverPointerPresence(statusButton: true, content: false, popoverWindow: false)
        }, close: { [weak popover] in popover?.performClose(nil) })
      let delegate = NativePopoverTestDelegate(controller: controller)
      popover.delegate = delegate
      defer {
        popover.close()
        window.close()
        controller.reset()
      }
      window.orderFront(nil)
      controller.beginOpening()
      popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
      XCTAssertTrue(popover.isShown)
      try await waitForState(.interactive, on: controller, timeoutNanoseconds: 5_000_000_000)
      XCTAssertEqual(delegate.events, ["didShow"])
      controller.requestClose()
      try await waitForState(.closed, on: controller, timeoutNanoseconds: 5_000_000_000)
      XCTAssertFalse(popover.isShown)
      XCTAssertEqual(delegate.events, ["didShow", "willClose", "didClose"])
    }
  }

  private func makeController(
    pointer: TestPointerLocation,
    openingDelay: UInt64? = nil,
    completesClosing: Bool = true,
    close: @escaping @MainActor () -> Void
  ) -> PopoverHoverController {
    weak var closingController: PopoverHoverController?
    let controller = PopoverHoverController(
      openingNanoseconds: openingDelay ?? self.openingDelay,
      closeDelayNanoseconds: closeDelay,
      reconciliationNanoseconds: 15_000_000,
      pointerPresence: { pointer.presence },
      close: {
        close()
        if completesClosing { closingController?.reset() }
      }
    )
    closingController = controller
    return controller
  }

  private func waitForState(
    _ expected: PopoverHoverState,
    on controller: PopoverHoverController,
    timeoutNanoseconds: UInt64 = 500_000_000
  ) async throws {
    for _ in 0..<max(1, timeoutNanoseconds / 5_000_000) {
      if controller.state == expected { return }
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("Timed out waiting for \(expected); current state is \(controller.state)")
  }
}

@MainActor
private final class NativePopoverTestDelegate: NSObject, NSPopoverDelegate {
  let controller: PopoverHoverController
  var events: [String] = []

  init(controller: PopoverHoverController) {
    self.controller = controller
  }

  func popoverDidShow(_ notification: Notification) {
    events.append("didShow")
    controller.presentationDidShow()
  }

  func popoverWillClose(_ notification: Notification) {
    events.append("willClose")
    controller.beginClosing()
  }

  func popoverDidClose(_ notification: Notification) {
    events.append("didClose")
    controller.reset()
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
