import Foundation
import XCTest

@testable import Pulse

@MainActor
final class DashboardTaskControllerTests: XCTestCase {
  private func setup() throws -> (DashboardConfiguration, URL, Dashboard) {
    let suite = "PulseControllerWriteback.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseController-\(UUID().uuidString).md")
    let text = """
      ---
      dashboard: true
      columns:
        - name: Inbox
          color: "#123456"
          type: todo
      ---
      ## Inbox
      ### Card
      - [ ] First
      - [ ] Second
      """
    try Data(text.utf8).write(to: url)
    addTeardownBlock {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: url)
    }
    let config = DashboardConfiguration(defaults: defaults)
    try config.saveDashboard(url: url)
    return (config, url, try ApexDashboardParser().parse(contents: text, fileURL: url))
  }

  private func waitUntil(_ condition: () async -> Bool) async throws {
    for _ in 0..<1_000 {
      if await condition() { return }
      try await Task.sleep(for: .milliseconds(1))
    }
    XCTFail("Timed out waiting for controlled operation")
  }

  func testPendingPreventsDuplicateClickAndConfirmsOnlyAfterPersistence() async throws {
    let (config, _, original) = try setup()
    let store = ControlledDashboardStore()
    let controller = DashboardTaskController(configuration: config, fileStore: store)
    let initial = controller.requestRefresh()
    try await waitUntil { await store.loadCount == 1 }
    await store.finishLoad(0, result: .success(original))
    await initial.value
    let task = original.allTasks[0]
    let saving = try XCTUnwrap(controller.setCompleted(true, task: task))
    XCTAssertTrue(controller.pendingTaskIDs.contains(task.id))
    XCTAssertNil(controller.setCompleted(true, task: task))
    guard case .loaded(let whileSaving) = controller.state else {
      return XCTFail("List was unmounted")
    }
    XCTAssertFalse(whileSaving.allTasks[0].completed)
    try await waitUntil { await store.saveCount == 1 }
    let completed = try changed(original, index: 0, completed: true)
    await store.finishSave(0, result: .success(completed))
    await saving.value
    XCTAssertTrue(controller.pendingTaskIDs.isEmpty)
    guard case .loaded(let confirmed) = controller.state else {
      return XCTFail("Expected loaded result")
    }
    XCTAssertTrue(confirmed.allTasks[0].completed)
    XCTAssertEqual(confirmed.allTasks.map(\.id), original.allTasks.map(\.id))
    XCTAssertNil(controller.saveFailure)
  }

  func testDifferentTasksCanBePendingWithoutBlockingListAndRefresh() async throws {
    let (config, url, _) = try setup()
    let controller = DashboardTaskController(configuration: config)
    await controller.refresh()
    guard case .loaded(let original) = controller.state else {
      return XCTFail("Expected initial dashboard")
    }
    let one = try XCTUnwrap(controller.setCompleted(true, task: original.allTasks[0]))
    let two = try XCTUnwrap(controller.setCompleted(true, task: original.allTasks[1]))
    XCTAssertEqual(controller.pendingTaskIDs.count, 2)
    await one.value
    await two.value
    await controller.refresh()
    guard case .loaded(let confirmed) = controller.state else {
      return XCTFail("Expected refreshed dashboard")
    }
    XCTAssertEqual(confirmed.allTasks.map(\.completed), [true, true])
    XCTAssertEqual(confirmed.allTasks.map(\.id), original.allTasks.map(\.id))
    let restored = DashboardTaskController(configuration: config)
    await restored.refresh()
    guard case .loaded(let reopened) = restored.state else {
      return XCTFail("Expected restored dashboard")
    }
    XCTAssertEqual(reopened.allTasks.map(\.completed), [true, true])
    XCTAssertEqual(
      try ApexDashboardParser().parse(data: Data(contentsOf: url), fileURL: url).allTasks.map(
        \.completed), [true, true])
  }

  func testRefreshRetainsMountedSnapshotUntilReadCompletes() async throws {
    let (config, _, original) = try setup()
    let store = ControlledDashboardStore()
    let controller = DashboardTaskController(configuration: config, fileStore: store)
    let initial = controller.requestRefresh()
    try await waitUntil { await store.loadCount == 1 }
    await store.finishLoad(0, result: .success(original))
    await initial.value
    let refreshing = controller.requestRefresh()
    try await waitUntil { await store.loadCount == 2 }
    XCTAssertTrue(controller.isRefreshing)
    XCTAssertEqual(controller.state, .loaded(original))
    await store.finishLoad(1, result: .success(original))
    await refreshing.value
    XCTAssertFalse(controller.isRefreshing)
  }

  func testRemovalIgnoresOldReadAndWriteReplies() async throws {
    let (config, _, original) = try setup()
    let store = ControlledDashboardStore()
    let controller = DashboardTaskController(configuration: config, fileStore: store)
    let loading = controller.requestRefresh()
    try await waitUntil { await store.loadCount == 1 }
    controller.removeDashboard()
    await store.finishLoad(0, result: .success(original))
    await loading.value
    XCTAssertEqual(controller.state, .notConfigured)
    try config.saveDashboard(url: original.fileURL)
    let reloading = controller.requestRefresh()
    try await waitUntil { await store.loadCount == 2 }
    await store.finishLoad(1, result: .success(original))
    await reloading.value
    let saving = try XCTUnwrap(controller.setCompleted(true, task: original.allTasks[0]))
    try await waitUntil { await store.saveCount == 1 }
    controller.removeDashboard()
    await store.finishSave(0, result: .success(try changed(original, index: 0, completed: true)))
    await saving.value
    XCTAssertEqual(controller.state, .notConfigured)
    XCTAssertTrue(controller.pendingTaskIDs.isEmpty)
    XCTAssertNil(controller.saveFailure)
  }

  func testLaterReadCannotBeOverwrittenByEarlierSaveReply() async throws {
    let (config, _, original) = try setup()
    let store = ControlledDashboardStore()
    let controller = DashboardTaskController(configuration: config, fileStore: store)
    let initial = controller.requestRefresh()
    try await waitUntil { await store.loadCount == 1 }
    await store.finishLoad(0, result: .success(original))
    await initial.value
    let saving = try XCTUnwrap(controller.setCompleted(true, task: original.allTasks[0]))
    try await waitUntil { await store.saveCount == 1 }
    let refreshing = controller.requestRefresh()
    try await waitUntil { await store.loadCount == 2 }
    let latest = try changed(
      try changed(original, index: 0, completed: true), index: 1, completed: true)
    await store.finishLoad(1, result: .success(latest))
    await refreshing.value
    await store.finishSave(0, result: .success(try changed(original, index: 0, completed: true)))
    await saving.value
    guard case .loaded(let result) = controller.state else {
      return XCTFail("Expected loaded dashboard")
    }
    XCTAssertEqual(result.allTasks.map(\.completed), [true, true])
  }

  func testFailureReloadsActualStateAndKeepsExplicitRetryIntent() async throws {
    let (config, _, original) = try setup()
    let store = ControlledDashboardStore()
    let controller = DashboardTaskController(configuration: config, fileStore: store)
    let initial = controller.requestRefresh()
    try await waitUntil { await store.loadCount == 1 }
    await store.finishLoad(0, result: .success(original))
    await initial.value
    let saving = try XCTUnwrap(controller.setCompleted(true, task: original.allTasks[0]))
    try await waitUntil { await store.saveCount == 1 }
    await store.finishSave(0, result: .failure(DashboardWriteError.verificationFailed))
    try await waitUntil { await store.loadCount == 2 }
    let actual = try changed(original, index: 0, completed: true)
    await store.finishLoad(1, result: .success(actual))
    await saving.value
    guard case .loaded(let result) = controller.state else {
      return XCTFail("Expected actual state")
    }
    XCTAssertTrue(result.allTasks[0].completed)  // No blind UI rollback after an uncertain save.
    XCTAssertNotNil(controller.saveFailure)
    XCTAssertTrue(controller.pendingTaskIDs.isEmpty)
    let retry = try XCTUnwrap(controller.retrySave())
    try await waitUntil { await store.saveCount == 2 }
    let desiredStates = await store.desiredStates()
    XCTAssertEqual(desiredStates, [true, true])
    await store.finishSave(1, result: .success(actual))
    await retry.value
    XCTAssertNil(controller.saveFailure)
  }

  func testPermissionFailureOffersReselectionAndDoesNotConfirmCompletion() async throws {
    let (config, _, original) = try setup()
    let store = ControlledDashboardStore()
    let controller = DashboardTaskController(configuration: config, fileStore: store)
    let initial = controller.requestRefresh()
    try await waitUntil { await store.loadCount == 1 }
    await store.finishLoad(0, result: .success(original))
    await initial.value
    let saving = try XCTUnwrap(controller.setCompleted(true, task: original.allTasks[0]))
    try await waitUntil { await store.saveCount == 1 }
    await store.finishSave(0, result: .failure(DashboardWriteError.permissionDenied))
    try await waitUntil { await store.loadCount == 2 }
    await store.finishLoad(1, result: .success(original))
    await saving.value
    XCTAssertTrue(controller.saveFailure?.needsReselection == true)
    guard case .loaded(let result) = controller.state else {
      return XCTFail("Expected loaded dashboard")
    }
    XCTAssertFalse(result.allTasks[0].completed)
  }

  func testInvalidBookmarkReportsReselectionInsteadOfMissingFile() async throws {
    let suite = "PulseBrokenBookmark.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Data([1, 2, 3]), forKey: "apexDashboardBookmark")
    let controller = DashboardTaskController(
      configuration: DashboardConfiguration(defaults: defaults))
    await controller.refresh()
    guard case .readError(let message) = controller.state else {
      return XCTFail("Expected bookmark error")
    }
    XCTAssertTrue(message.contains("Choose the file again"))
  }

  private func changed(_ dashboard: Dashboard, index: Int, completed: Bool) throws -> Dashboard {
    var data = dashboard.sourceData
    data[try XCTUnwrap(dashboard.allTasks[index].source?.stateByteOffset)] = completed ? 120 : 32
    return try ApexDashboardParser().parse(data: data, fileURL: dashboard.fileURL)
  }

  func testQueuedSaveDoesNotStartAfterSelectionRemoval() async throws {
    let (config, url, _) = try setup()
    let controller = DashboardTaskController(configuration: config)
    await controller.refresh()
    guard case .loaded(let original) = controller.state else {
      return XCTFail("Expected dashboard")
    }
    let saving = try XCTUnwrap(controller.setCompleted(true, task: original.allTasks[0]))
    controller.removeDashboard()
    await saving.value
    XCTAssertEqual(controller.state, .notConfigured)
    XCTAssertEqual(try Data(contentsOf: url), original.sourceData)
  }

  func testActualFileObservationOrdersResultsIndependentlyOfTaskIssuance() async throws {
    let (config, _, original) = try setup()
    let store = ControlledDashboardStore()
    let controller = DashboardTaskController(configuration: config, fileStore: store)
    let first = controller.requestRefresh()
    try await waitUntil { await store.loadCount == 1 }
    var initialSnapshot = original
    let instant = ContinuousClock.now
    initialSnapshot.observedAt = instant
    await store.finishLoad(0, result: .success(initialSnapshot))
    await first.value
    let saving = try XCTUnwrap(controller.setCompleted(true, task: original.allTasks[0]))
    try await waitUntil { await store.saveCount == 1 }
    let refreshing = controller.requestRefresh()
    try await waitUntil { await store.loadCount == 2 }
    var earlierRead = original
    earlierRead.observedAt = instant.advanced(by: .milliseconds(1))
    await store.finishLoad(1, result: .success(earlierRead))
    await refreshing.value
    var latestWrite = try changed(original, index: 0, completed: true)
    latestWrite.observedAt = instant.advanced(by: .milliseconds(2))
    await store.finishSave(0, result: .success(latestWrite))
    await saving.value
    guard case .loaded(let result) = controller.state else {
      return XCTFail("Expected confirmed write")
    }
    XCTAssertTrue(result.allTasks[0].completed)
    XCTAssertEqual(result.allTasks[0].id, original.allTasks[0].id)
  }
}

private actor ControlledDashboardStore: DashboardFileStoring {
  private var reads: [CheckedContinuation<Dashboard, Error>?] = []
  private var writes: [CheckedContinuation<Dashboard, Error>?] = []
  private var states: [Bool] = []
  var loadCount: Int { reads.count }
  var saveCount: Int { writes.count }

  func load(fileURL: URL) async throws -> Dashboard {
    try await withCheckedThrowingContinuation { reads.append($0) }
  }

  func setCompleted(_ completed: Bool, task: DashboardTask, snapshot: Dashboard, fileURL: URL)
    async throws -> Dashboard
  {
    states.append(completed)
    return try await withCheckedThrowingContinuation { writes.append($0) }
  }

  func finishLoad(_ index: Int, result: Result<Dashboard, Error>) {
    reads[index]?.resume(with: result)
    reads[index] = nil
  }

  func finishSave(_ index: Int, result: Result<Dashboard, Error>) {
    writes[index]?.resume(with: result)
    writes[index] = nil
  }

  func desiredStates() -> [Bool] { states }
}
