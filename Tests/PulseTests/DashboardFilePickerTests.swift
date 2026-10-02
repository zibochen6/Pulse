import Foundation
import XCTest

@testable import Pulse

@MainActor
final class DashboardFilePickerTests: XCTestCase {
  func testWaitsForCompletedPopoverCloseAndPresentsOnce() {
    let panel = FakeDashboardPanel()
    var closes = 0
    let picker = DashboardFilePicker(
      panel: panel,
      closePopover: {
        closes += 1
        return true
      },
      onSelection: { _ in }, onFinish: {})
    picker.requestSelection()
    picker.requestSelection()
    XCTAssertTrue(picker.isSelecting)
    XCTAssertEqual(closes, 1)
    XCTAssertEqual(panel.presentCount, 0)
    picker.popoverDidClose()
    picker.popoverDidClose()
    XCTAssertEqual(panel.presentCount, 1)
    picker.requestSelection()
    XCTAssertEqual(panel.focusCount, 1)
    XCTAssertEqual(panel.presentCount, 1)
    panel.finish(.cancelled)
    XCTAssertFalse(picker.isSelecting)
  }

  func testAlreadyClosedPopoverPresentsImmediatelyAndCancelDoesNotSelect() {
    let panel = FakeDashboardPanel()
    var selections = 0
    var restores = 0
    let picker = DashboardFilePicker(
      panel: panel, closePopover: { false }, onSelection: { _ in selections += 1 },
      onFinish: { restores += 1 })
    picker.requestSelection()
    XCTAssertEqual(panel.presentCount, 1)
    panel.finish(.cancelled)
    XCTAssertEqual(selections, 0)
    XCTAssertEqual(restores, 1)
    XCTAssertFalse(picker.isSelecting)
    picker.requestSelection()
    XCTAssertEqual(panel.presentCount, 2)
    panel.finish(.cancelled)
  }

  func testMissingCloseCallbackRecoversOnlyAfterWindowActuallyDisappears() async throws {
    let panel = FakeDashboardPanel()
    let visibility = FakePopoverVisibility()
    let picker = DashboardFilePicker(
      panel: panel, closePopover: { true }, isPopoverVisible: { visibility.isVisible },
      closeWaitNanoseconds: 200_000_000, closeCheckNanoseconds: 1_000_000,
      onSelection: { _ in }, onFinish: {})
    picker.requestSelection()
    try await Task.sleep(for: .milliseconds(5))
    XCTAssertEqual(panel.presentCount, 0, "Never open over the closing animation")
    visibility.isVisible = false
    try await waitUntil { panel.presentCount == 1 }
    picker.popoverDidClose()
    XCTAssertEqual(panel.presentCount, 1, "A late delegate callback must not present twice")
    panel.finish(.cancelled)
    XCTAssertFalse(picker.isSelecting)
  }

  func testStuckCloseReportsErrorAndAllowsAnotherSelection() async throws {
    let panel = FakeDashboardPanel()
    let visibility = FakePopoverVisibility()
    var finishes = 0
    let picker = DashboardFilePicker(
      panel: panel, closePopover: { true }, isPopoverVisible: { visibility.isVisible },
      closeWaitNanoseconds: 10_000_000, closeCheckNanoseconds: 1_000_000,
      onSelection: { _ in }, onFinish: { finishes += 1 })
    picker.requestSelection()
    try await waitUntil { !picker.isSelecting }
    XCTAssertNotNil(picker.errorMessage)
    XCTAssertEqual(panel.presentCount, 0)
    XCTAssertEqual(finishes, 1)
    picker.popoverDidClose()
    XCTAssertEqual(panel.presentCount, 0)
    visibility.isVisible = false
    picker.requestSelection()
    try await waitUntil { panel.presentCount == 1 }
    XCTAssertNil(picker.errorMessage)
    panel.finish(.cancelled)
    XCTAssertEqual(finishes, 2)
  }

  func testNormalCloseCancelsRecoveryAndRepeatedRequestsOnlyFocusPanel() async throws {
    let panel = FakeDashboardPanel()
    let picker = DashboardFilePicker(
      panel: panel, closePopover: { true }, isPopoverVisible: { true },
      closeWaitNanoseconds: 10_000_000, closeCheckNanoseconds: 1_000_000,
      onSelection: { _ in }, onFinish: {})
    picker.requestSelection()
    picker.popoverDidClose()
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertNil(picker.errorMessage)
    XCTAssertTrue(picker.isSelecting)
    picker.requestSelection()
    XCTAssertEqual(panel.presentCount, 1)
    XCTAssertEqual(panel.focusCount, 1)
    panel.finish(.cancelled)
  }

  func testSynchronousCloseCallbackCannotPresentTwice() {
    let panel = FakeDashboardPanel()
    weak var closingPicker: DashboardFilePicker?
    let picker = DashboardFilePicker(
      panel: panel,
      closePopover: {
        closingPicker?.popoverDidClose()
        return false
      },
      onSelection: { _ in }, onFinish: {})
    closingPicker = picker
    picker.requestSelection()
    XCTAssertEqual(panel.presentCount, 1)
    panel.finish(.cancelled)
  }

  func testFailureRestoresSettingsWithRetryMessage() {
    let panel = FakeDashboardPanel()
    var restores = 0
    let picker = DashboardFilePicker(
      panel: panel, closePopover: { false }, onSelection: { _ in XCTFail("No selection expected") },
      onFinish: { restores += 1 })
    picker.requestSelection()
    panel.finish(.failed)
    XCTAssertNotNil(picker.errorMessage)
    XCTAssertEqual(restores, 1)
    XCTAssertFalse(picker.isSelecting)
    picker.requestSelection()
    XCTAssertNil(picker.errorMessage)
    panel.finish(.cancelled)
  }

  func testSelectionIsProcessedOnceAndWaitsForPersistenceBeforeRestoring() async throws {
    let panel = FakeDashboardPanel()
    var received: [URL] = []
    var finishCount = 0
    var continuation: CheckedContinuation<Void, Never>?
    let picker = DashboardFilePicker(
      panel: panel, closePopover: { false },
      onSelection: { url in
        received.append(url)
        await withCheckedContinuation { continuation = $0 }
      }, onFinish: { finishCount += 1 })
    let url = URL(fileURLWithPath: "/tmp/fictional-dashboard.md")
    picker.requestSelection()
    panel.finish(.selected(url))
    panel.finish(.selected(url))
    picker.requestSelection()
    try await waitUntil { continuation != nil }
    XCTAssertEqual(received, [url])
    XCTAssertTrue(picker.isSelecting)
    XCTAssertEqual(finishCount, 0)
    XCTAssertEqual(panel.presentCount, 1)
    continuation?.resume()
    try await waitUntil { !picker.isSelecting }
    XCTAssertEqual(finishCount, 1)
  }

  func testSelectingAndReselectingTemporaryDashboardUpdatesConnectionWithoutChangingSource()
    async throws
  {
    let suite = "PulsePicker.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulsePicker-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
    let fixture = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "sample-apex-dashboard", withExtension: "md"))
    let first = directory.appendingPathComponent("first.md")
    let second = directory.appendingPathComponent("second.md")
    try Data(contentsOf: fixture).write(to: first)
    try Data(contentsOf: fixture).write(to: second)
    let tasks = DashboardTaskController(configuration: DashboardConfiguration(defaults: defaults))
    let source = TaskSourceConfiguration(defaults: defaults)
    let panel = FakeDashboardPanel()
    let pages = PopoverPageController()
    let picker = DashboardFilePicker(
      panel: panel, closePopover: { false },
      onSelection: { url in await tasks.saveDashboard(url: url) },
      onFinish: { pages.showSettings(.tasks) })
    picker.requestSelection()
    panel.finish(.selected(first))
    try await waitUntil { !picker.isSelecting }
    guard case .loaded(let loaded) = tasks.state else { return XCTFail("Expected connected file") }
    XCTAssertEqual(loaded.fileURL.standardizedFileURL, first.standardizedFileURL)
    XCTAssertEqual(source.source, .local)
    XCTAssertEqual(pages.page, .settings(.tasks))

    picker.requestSelection()
    panel.finish(.cancelled)
    XCTAssertEqual(
      try tasks.configuration.resolveDashboardURL().standardizedFileURL, first.standardizedFileURL)
    picker.requestSelection()
    panel.finish(.selected(second))
    try await waitUntil { !picker.isSelecting }
    XCTAssertEqual(
      try tasks.configuration.resolveDashboardURL().standardizedFileURL, second.standardizedFileURL)
    XCTAssertEqual(source.source, .local)

    try Data("not an Apex Dashboard".utf8).write(to: second)
    picker.requestSelection()
    panel.finish(.selected(second))
    try await waitUntil { !picker.isSelecting }
    guard case .parseError = tasks.state else { return XCTFail("Expected explicit parse failure") }
    XCTAssertEqual(pages.page, .settings(.tasks))
  }

  private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<1_000 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(1))
    }
    XCTFail("Picker completion timed out")
  }
}

@MainActor
private final class FakePopoverVisibility {
  var isVisible = true
}

@MainActor
private final class FakeDashboardPanel: DashboardFilePanelPresenting {
  var presentCount = 0
  var focusCount = 0
  private var completion: (@MainActor (DashboardFilePanelResult) -> Void)?

  func present(completion: @escaping @MainActor (DashboardFilePanelResult) -> Void) {
    presentCount += 1
    self.completion = completion
  }
  func focus() { focusCount += 1 }
  func finish(_ result: DashboardFilePanelResult) { completion?(result) }
}
