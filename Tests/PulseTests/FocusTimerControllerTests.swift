import XCTest

@testable import Pulse

@MainActor
final class FocusTimerControllerTests: XCTestCase {
  func testDefaultSessionEndsAtThirtyMinutesEvenAfterRepeatedStart() {
    let start = ContinuousClock.now
    var now = start
    var chimes = 0
    let timer = FocusTimerController(now: { now }, onCompletion: { chimes += 1 })

    timer.start()
    now = start.advanced(by: .seconds(1799))
    timer.start()
    timer.finishIfDue()

    XCTAssertTrue(timer.isRunning)
    XCTAssertEqual(chimes, 0)

    now = start.advanced(by: .seconds(1800))
    timer.finishIfDue()
    timer.finishIfDue()

    XCTAssertFalse(timer.isRunning)
    XCTAssertEqual(chimes, 1)
  }

  func testCancelledSessionStaysSilentAndReplacementGetsItsOwnDeadline() {
    let start = ContinuousClock.now
    var now = start
    var chimes = 0
    let timer = FocusTimerController(now: { now }, onCompletion: { chimes += 1 })

    timer.start()
    now = start.advanced(by: .seconds(900))
    timer.cancel()
    XCTAssertFalse(timer.isRunning)
    XCTAssertEqual(chimes, 0)
    timer.start()

    now = start.advanced(by: .seconds(1801))
    timer.finishIfDue()
    XCTAssertTrue(timer.isRunning)
    XCTAssertEqual(chimes, 0)

    now = start.advanced(by: .seconds(2701))
    timer.finishIfDue()
    timer.finishIfDue()
    XCTAssertFalse(timer.isRunning)
    XCTAssertEqual(chimes, 1)
  }

  func testWakeReconciliationCompletesOverdueSessionOnlyOnce() {
    let start = ContinuousClock.now
    var now = start
    var chimes = 0
    let timer = FocusTimerController(now: { now }, onCompletion: { chimes += 1 })

    timer.start()
    now = start.advanced(by: .seconds(3600))
    timer.finishIfDue()
    timer.finishIfDue()

    XCTAssertFalse(timer.isRunning)
    XCTAssertEqual(chimes, 1)
  }

  func testScheduledCompletionAfterRapidCancelAndRestart() async throws {
    var chimes = 0
    let timer = FocusTimerController(duration: .milliseconds(20), onCompletion: { chimes += 1 })

    timer.start()
    timer.cancel()
    timer.start()
    XCTAssertTrue(timer.isRunning)
    XCTAssertEqual(chimes, 0)

    let timeout = ContinuousClock.now.advanced(by: .seconds(2))
    while timer.isRunning && ContinuousClock.now < timeout {
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertFalse(timer.isRunning)
    XCTAssertEqual(chimes, 1)
  }

  func testFocusSessionDefersAutomaticInstallWithoutBlockingExplicitExit() {
    let timer = FocusTimerController()
    var policy = PulseExitPolicy(
      popoverOpen: false, settingsOpen: false,
      hasUnsavedEdits: false, hasPendingWrites: false)
    XCTAssertTrue(policy.canInstallAutomatically)

    timer.start()
    policy.focusSessionActive = timer.isRunning
    XCTAssertFalse(policy.canInstallAutomatically)
    XCTAssertFalse(policy.requiresDiscardConfirmation)
    XCTAssertFalse(policy.mustWaitForWrites)

    timer.cancel()
    policy.focusSessionActive = timer.isRunning
    XCTAssertTrue(policy.canInstallAutomatically)
  }
}
