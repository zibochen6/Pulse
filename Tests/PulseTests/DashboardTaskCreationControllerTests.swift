import Foundation
import XCTest

@testable import Pulse

@MainActor
final class DashboardTaskCreationControllerTests: XCTestCase {
  private func setup() throws -> (DashboardConfiguration, URL, Dashboard) {
    let suite = "PulseCreationController.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseCreationController-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("dashboard.md")
    let contents = """
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
      - [ ] Last
      """
    try Data(contents.utf8).write(to: url)
    addTeardownBlock {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
    let configuration = DashboardConfiguration(defaults: defaults)
    try configuration.saveDashboard(url: url)
    let snapshot = try ApexDashboardParser().parse(contents: contents, fileURL: url)
    return (configuration, url, snapshot)
  }

  private func request(_ snapshot: Dashboard) -> DashboardTaskCreationRequest {
    DashboardTaskCreationRequest(
      text: "Create fictional task",
      destination: DashboardTaskDestination(
        column: snapshot.columns[0], card: snapshot.columns[0].cards[0]),
      snapshot: snapshot)
  }

  private func waitUntil(_ condition: () async -> Bool) async throws {
    for _ in 0..<1_000 {
      if await condition() { return }
      try await Task.sleep(for: .milliseconds(1))
    }
    XCTFail("Timed out waiting for controlled creation")
  }

  private func loadedController(
    configuration: DashboardConfiguration, snapshot: Dashboard, store: ControlledCreationStore
  ) async throws -> DashboardTaskController {
    let controller = DashboardTaskController(configuration: configuration, fileStore: store)
    let loading = controller.requestRefresh()
    try await waitUntil { await store.loadCount == 1 }
    await store.finishLoad(0, result: .success(snapshot))
    await loading.value
    return controller
  }

  private func created(_ request: DashboardTaskCreationRequest) throws -> Dashboard {
    let patch = try DashboardTaskInsertion.makePatch(for: request, in: request.snapshot)
    let parsed = try ApexDashboardParser().parse(
      data: patch.data, fileURL: request.snapshot.fileURL)
    return DashboardTaskInsertion.preservingIdentities(
      in: parsed, from: request.snapshot, patch: patch)
  }

  func testPendingPreventsDoubleSubmitAndPublishesOnlyVerifiedSuccess() async throws {
    let (configuration, _, snapshot) = try setup()
    let store = ControlledCreationStore()
    let controller = try await loadedController(
      configuration: configuration, snapshot: snapshot, store: store)
    let intent = request(snapshot)
    let saving = try XCTUnwrap(controller.addTask(request: intent))
    XCTAssertTrue(controller.isAddingTask)
    XCTAssertNil(controller.addTask(request: intent))
    XCTAssertEqual(controller.state, .loaded(snapshot))
    try await waitUntil { await store.addCount == 1 }
    await store.finishAdd(0, result: .success(try created(intent)))
    let success = await saving.value
    XCTAssertTrue(success)
    XCTAssertFalse(controller.isAddingTask)
    guard case .loaded(let result) = controller.state else { return XCTFail("Expected loaded") }
    XCTAssertEqual(result.allTasks.count, 3)
    XCTAssertEqual(Array(result.allTasks.prefix(2)).map(\.id), snapshot.allTasks.map(\.id))
    XCTAssertNil(controller.addFailure)
  }

  func testFailureRecoversFileAndKeepsSameRequestForRetry() async throws {
    let (configuration, _, snapshot) = try setup()
    let store = ControlledCreationStore()
    let controller = try await loadedController(
      configuration: configuration, snapshot: snapshot, store: store)
    let intent = request(snapshot)
    let saving = try XCTUnwrap(controller.addTask(request: intent))
    try await waitUntil { await store.addCount == 1 }
    await store.finishAdd(0, result: .failure(DashboardWriteError.permissionDenied))
    try await waitUntil { await store.loadCount == 2 }
    await store.finishLoad(1, result: .success(snapshot))
    let success = await saving.value
    XCTAssertFalse(success)
    XCTAssertTrue(controller.addFailure?.needsReselection == true)
    XCTAssertEqual(controller.addFailure?.request.id, intent.id)
    XCTAssertEqual(controller.state, .loaded(snapshot))
    let retry = try XCTUnwrap(controller.retryAddTask())
    try await waitUntil { await store.addCount == 2 }
    let ids = await store.requestIDs()
    XCTAssertEqual(ids, [intent.id, intent.id])
    await store.finishAdd(1, result: .success(try created(intent)))
    let retried = await retry.value
    XCTAssertTrue(retried)
    XCTAssertNil(controller.addFailure)
  }

  func testUncertainSaveReloadsRealityRatherThanAddingOptimisticDuplicate() async throws {
    let (configuration, _, snapshot) = try setup()
    let store = ControlledCreationStore()
    let controller = try await loadedController(
      configuration: configuration, snapshot: snapshot, store: store)
    let intent = request(snapshot)
    let persisted = try created(intent)
    let saving = try XCTUnwrap(controller.addTask(request: intent))
    try await waitUntil { await store.addCount == 1 }
    await store.finishAdd(0, result: .failure(DashboardWriteError.verificationFailed))
    try await waitUntil { await store.loadCount == 2 }
    await store.finishLoad(1, result: .success(persisted))
    let success = await saving.value
    XCTAssertFalse(success)
    guard case .loaded(let actual) = controller.state else {
      return XCTFail("Expected actual file")
    }
    XCTAssertEqual(actual.allTasks.count, 3)
    XCTAssertEqual(controller.addFailure?.request.id, intent.id)
    let retry = try XCTUnwrap(controller.retryAddTask())
    try await waitUntil { await store.addCount == 2 }
    await store.finishAdd(1, result: .success(persisted))
    let retried = await retry.value
    XCTAssertTrue(retried)
    guard case .loaded(let result) = controller.state else { return XCTFail("Expected file") }
    XCTAssertEqual(result.allTasks.count, 3)
  }

  func testRemovalIgnoresLateCreationResultAndClearsPending() async throws {
    let (configuration, _, snapshot) = try setup()
    let store = ControlledCreationStore()
    let controller = try await loadedController(
      configuration: configuration, snapshot: snapshot, store: store)
    let intent = request(snapshot)
    let saving = try XCTUnwrap(controller.addTask(request: intent))
    try await waitUntil { await store.addCount == 1 }
    controller.removeDashboard()
    XCTAssertFalse(controller.isAddingTask)
    await store.finishAdd(0, result: .success(try created(intent)))
    let success = await saving.value
    XCTAssertFalse(success)
    XCTAssertEqual(controller.state, .notConfigured)
    XCTAssertNil(controller.addFailure)
  }

  func testQueuedCreationDoesNotWriteAfterSelectionRemoval() async throws {
    let (configuration, url, snapshot) = try setup()
    let controller = DashboardTaskController(configuration: configuration)
    await controller.refresh()
    let saving = try XCTUnwrap(controller.addTask(request: request(snapshot)))
    controller.removeDashboard()
    let success = await saving.value
    XCTAssertFalse(success)
    XCTAssertEqual(try Data(contentsOf: url), snapshot.sourceData)
  }

  func testRealControllerReopensPersistedNewTaskAndKeepsOldRowIdentities() async throws {
    let (configuration, url, _) = try setup()
    let controller = DashboardTaskController(configuration: configuration)
    await controller.refresh()
    guard case .loaded(let snapshot) = controller.state else {
      return XCTFail("Expected dashboard")
    }
    let intent = request(snapshot)
    let saving = try XCTUnwrap(controller.addTask(request: intent))
    let success = await saving.value
    XCTAssertTrue(success)
    guard case .loaded(let result) = controller.state else { return XCTFail("Expected dashboard") }
    XCTAssertEqual(Array(result.allTasks.prefix(2)).map(\.id), snapshot.allTasks.map(\.id))
    let reopened = DashboardTaskController(configuration: configuration)
    await reopened.refresh()
    guard case .loaded(let actual) = reopened.state else { return XCTFail("Expected reopened") }
    XCTAssertEqual(actual.allTasks.count, 3)
    XCTAssertEqual(actual.allTasks[2].text, intent.text)
    XCTAssertEqual(try Data(contentsOf: url), actual.sourceData)
  }

  func testRecreatedConfigurationResolvesBookmarkAfterAtomicReplacement() async throws {
    let (_, url, snapshot) = try setup()
    let suite = "PulseCreationBookmark.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let configuration = DashboardConfiguration(defaults: defaults)
    try configuration.saveDashboard(url: url)
    let controller = DashboardTaskController(configuration: configuration)
    await controller.refresh()
    let intent = request(snapshot)
    let saving = try XCTUnwrap(controller.addTask(request: intent))
    let success = await saving.value
    XCTAssertTrue(success)
    let recreated = DashboardConfiguration(defaults: defaults)
    XCTAssertEqual(try recreated.resolveDashboardURL().standardizedFileURL, url.standardizedFileURL)
    let reopened = DashboardTaskController(configuration: recreated)
    await reopened.refresh()
    guard case .loaded(let actual) = reopened.state else {
      return XCTFail("Bookmark lost replacement")
    }
    XCTAssertEqual(actual.allTasks.count, 3)
    XCTAssertEqual(actual.allTasks[2].pulseCreationIdentifier, intent.creationIdentifier)
  }
}

private actor ControlledCreationStore: DashboardFileStoring {
  private var loads: [CheckedContinuation<Dashboard, Error>?] = []
  private var adds: [CheckedContinuation<Dashboard, Error>?] = []
  private var requests: [DashboardTaskCreationRequest] = []
  var loadCount: Int { loads.count }
  var addCount: Int { adds.count }

  func load(fileURL: URL) async throws -> Dashboard {
    try await withCheckedThrowingContinuation { loads.append($0) }
  }

  func setCompleted(_ completed: Bool, task: DashboardTask, snapshot: Dashboard, fileURL: URL)
    async throws -> Dashboard
  {
    throw DashboardWriteError.saveFailed
  }

  func addTask(request: DashboardTaskCreationRequest, fileURL: URL) async throws -> Dashboard {
    requests.append(request)
    return try await withCheckedThrowingContinuation { adds.append($0) }
  }

  func finishLoad(_ index: Int, result: Result<Dashboard, Error>) {
    let continuation = loads[index]
    loads[index] = nil
    continuation?.resume(with: result)
  }

  func finishAdd(_ index: Int, result: Result<Dashboard, Error>) {
    let continuation = adds[index]
    adds[index] = nil
    continuation?.resume(with: result)
  }

  func requestIDs() -> [UUID] { requests.map(\.id) }
}
