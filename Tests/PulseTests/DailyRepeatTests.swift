import Foundation
import XCTest

@testable import Pulse

/// Daily-repeat behaviour that spans the store and the main-actor controller.
/// Every case uses a temporary directory and explicit dates, so results never
/// depend on the developer's real task file or on what time the test runs.
@MainActor
final class DailyRepeatControllerTests: XCTestCase {
  private func store() throws -> LocalTaskStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseDailyRepeat-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return LocalTaskStore(fileURL: directory.appendingPathComponent("tasks.json"))
  }

  private func waitUntil(_ condition: () async -> Bool) async throws {
    for _ in 0..<1_000 {
      if await condition() { return }
      try await Task.sleep(for: .milliseconds(1))
    }
    XCTFail("Timed out waiting for controlled operation")
  }

  func testSaveTaskPersistsRepeatFlagAndFilterHelpersSplitCompletion() async throws {
    let store = try store()
    let controller = LocalTaskController(store: store)
    await controller.refresh()
    let dailySaved = await controller.saveTask(
      id: nil, text: "Daily", tagIDs: [], newTagNames: [], repeatsDaily: true)
    XCTAssertTrue(dailySaved)
    let plainSaved = await controller.saveTask(id: nil, text: "Plain", tagIDs: [], newTagNames: [])
    XCTAssertTrue(plainSaved)
    let daily = try XCTUnwrap(controller.document?.tasks.first(where: { $0.text == "Daily" }))
    XCTAssertTrue(daily.repeatsDaily)
    XCTAssertEqual(
      controller.incompleteTasks(matching: .all).map(\.text), ["Daily", "Plain"])
    XCTAssertEqual(controller.completedTasks(matching: .all), [])
    let completion = try XCTUnwrap(controller.setCompleted(true, taskID: daily.id))
    await completion.value
    XCTAssertEqual(controller.completedTasks(matching: .all).map(\.text), ["Daily"])
    XCTAssertEqual(controller.incompleteTasks(matching: .all).map(\.text), ["Plain"])
    // `.all` still means every task, and the helper preserves stored order.
    XCTAssertEqual(controller.tasks(matching: .all).map(\.text), ["Daily", "Plain"])
    // The flag survives a reload from disk, not just the in-memory document.
    let reopened = LocalTaskController(store: LocalTaskStore(fileURL: store.fileURL))
    await reopened.refresh()
    XCTAssertEqual(reopened.document, controller.document)
    XCTAssertTrue(try XCTUnwrap(reopened.document?.tasks.first).repeatsDaily)
    XCTAssertTrue(try XCTUnwrap(reopened.document?.tasks.first).completed)
  }

  func testSetCompletedOnRepeatingTaskRecordsTheDay() async throws {
    let store = try store()
    let controller = LocalTaskController(store: store)
    await controller.refresh()
    let saved = await controller.saveTask(
      id: nil, text: "Daily", tagIDs: [], newTagNames: [], repeatsDaily: true)
    XCTAssertTrue(saved)
    let id = try XCTUnwrap(controller.document?.tasks.first?.id)
    let completion = try XCTUnwrap(controller.setCompleted(true, taskID: id))
    await completion.value
    let task = try XCTUnwrap(controller.document?.tasks.first)
    XCTAssertTrue(task.completed)
    XCTAssertEqual(task.lastCompletedDay, Calendar.current.startOfDay(for: Date()))
    // Un-completing a daily task is allowed and clears the day so the manual
    // state cannot be mistaken for a completion.
    let undone = try XCTUnwrap(controller.setCompleted(false, taskID: id))
    await undone.value
    let reverted = try XCTUnwrap(controller.document?.tasks.first)
    XCTAssertFalse(reverted.completed)
    XCTAssertNil(reverted.lastCompletedDay)
    XCTAssertTrue(reverted.repeatsDaily)
  }

  func testResetRepeatingTasksReArmsOnlyEarlierDays() async throws {
    let store = try store()
    let yesterday = try XCTUnwrap(
      Calendar.current.date(byAdding: .day, value: -1, to: Date()))
    var document = try await store.mutate(
      .saveTask(id: nil, text: "Stale", tagIDs: [], newTagNames: [], repeatsDaily: true)
    ).document
    document = try await store.mutate(
      .saveTask(id: nil, text: "Fresh", tagIDs: [], newTagNames: [], repeatsDaily: true)
    ).document
    document = try await store.mutate(
      .saveTask(id: nil, text: "Plain", tagIDs: [], newTagNames: [])
    ).document
    let stale = document.tasks[0].id
    let fresh = document.tasks[1].id
    let plain = document.tasks[2].id
    _ = try await store.mutate(.completeRepeating(taskID: stale, completedAt: yesterday))
    _ = try await store.mutate(.completeRepeating(taskID: fresh, completedAt: Date()))
    _ = try await store.mutate(.setCompleted(taskID: plain, completed: true))
    let controller = LocalTaskController(store: store)
    await controller.refresh()
    await controller.resetRepeatingTasks()
    XCTAssertEqual(controller.document?.tasks.map(\.completed), [false, true, true])
    XCTAssertNil(controller.errorMessage)
    // Reopening the popover runs it again; the confirmed state does not change.
    let afterFirst = controller.document
    await controller.resetRepeatingTasks()
    XCTAssertEqual(controller.document, afterFirst)
  }

  func testResetRepeatingTasksWithoutLoadedDocumentDoesNotTouchDisk() async throws {
    let store = try store()
    let controller = LocalTaskController(store: store)
    await controller.resetRepeatingTasks()
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    XCTAssertNil(controller.errorMessage)
  }

  func testRepeatingCompletionFailureRetriesWithItsOriginalDay() async throws {
    let original = LocalTaskDocument(tasks: [
      LocalTask(text: "Daily", repeatsDaily: true), LocalTask(text: "Plain")
    ])
    let storage = RepeatControlledLocalTaskStore()
    let controller = LocalTaskController(store: storage)
    let loading = Task { await controller.refresh() }
    try await waitUntil { await storage.loadCount == 1 }
    await storage.finishLoad(0, result: .success(LocalTaskSnapshot(document: original)))
    await loading.value
    let daily = original.tasks[0].id
    let save = try XCTUnwrap(controller.setCompleted(true, taskID: daily))
    try await waitUntil { await storage.mutationCount == 1 }
    await storage.finishMutation(0, result: .failure(LocalTaskStoreError.saveFailed))
    try await waitUntil { await storage.loadCount == 2 }
    await storage.finishLoad(1, result: .success(LocalTaskSnapshot(document: original)))
    await save.value
    let failure = try XCTUnwrap(controller.completionFailures[daily])
    XCTAssertTrue(failure.repeatsDaily)
    XCTAssertTrue(failure.completed)
    XCTAssertEqual(failure.taskID, daily)
    // The recorded instant is what a retry reuses, so it must be the click day.
    XCTAssertTrue(Calendar.current.isDateInToday(failure.completedAt))
    XCTAssertEqual(controller.document, original)

    let retry = try XCTUnwrap(controller.retryCompletion(failure))
    try await waitUntil { await storage.mutationCount == 2 }
    var confirmed = original
    confirmed.tasks[0].completed = true
    confirmed.tasks[0].lastCompletedDay = Calendar.current.startOfDay(for: failure.completedAt)
    await storage.finishMutation(1, result: .success(LocalTaskSnapshot(document: confirmed)))
    await retry.value
    XCTAssertEqual(controller.document, confirmed)
    XCTAssertTrue(controller.completionFailures.isEmpty)
  }

  func testAnotherTasksSuccessKeepsRepeatingRetryData() async throws {
    let original = LocalTaskDocument(tasks: [
      LocalTask(text: "Daily", repeatsDaily: true), LocalTask(text: "Plain")
    ])
    let storage = RepeatControlledLocalTaskStore()
    let controller = LocalTaskController(store: storage)
    let loading = Task { await controller.refresh() }
    try await waitUntil { await storage.loadCount == 1 }
    await storage.finishLoad(0, result: .success(LocalTaskSnapshot(document: original)))
    await loading.value
    let dailyFailure = try XCTUnwrap(controller.setCompleted(true, taskID: original.tasks[0].id))
    let plainSuccess = try XCTUnwrap(controller.setCompleted(true, taskID: original.tasks[1].id))
    try await waitUntil { await storage.mutationCount == 2 }
    await storage.finishMutation(0, result: .failure(LocalTaskStoreError.saveFailed))
    try await waitUntil { await storage.loadCount == 2 }
    var secondConfirmed = original
    secondConfirmed.tasks[1].completed = true
    await storage.finishLoad(1, result: .success(LocalTaskSnapshot(document: secondConfirmed)))
    await dailyFailure.value
    let recorded = try XCTUnwrap(controller.completionFailures[original.tasks[0].id])
    await storage.finishMutation(1, result: .success(LocalTaskSnapshot(document: secondConfirmed)))
    await plainSuccess.value
    XCTAssertEqual(controller.completionFailures[original.tasks[0].id], recorded)
    XCTAssertNil(controller.completionFailures[original.tasks[1].id])
    XCTAssertTrue(recorded.repeatsDaily)
  }

  func testResetFailureReportsErrorAndPublishesConfirmedState() async throws {
    let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
    let original = LocalTaskDocument(tasks: [
      LocalTask(text: "Daily", completed: true, repeatsDaily: true, lastCompletedDay: yesterday)
    ])
    let storage = RepeatControlledLocalTaskStore()
    let controller = LocalTaskController(store: storage)
    let loading = Task { await controller.refresh() }
    try await waitUntil { await storage.loadCount == 1 }
    await storage.finishLoad(0, result: .success(LocalTaskSnapshot(document: original)))
    await loading.value
    let resetting = Task { await controller.resetRepeatingTasks() }
    try await waitUntil { await storage.mutationCount == 1 }
    XCTAssertEqual(controller.document, original)
    await storage.finishMutation(0, result: .failure(LocalTaskStoreError.saveFailed))
    try await waitUntil { await storage.loadCount == 2 }
    await storage.finishLoad(1, result: .success(LocalTaskSnapshot(document: original)))
    await resetting.value
    // Unconfirmed resets are never published; the failure surfaces normally.
    XCTAssertEqual(controller.document, original)
    XCTAssertNotNil(controller.errorMessage)
    XCTAssertFalse(controller.isSaving)
  }
}

private actor RepeatControlledLocalTaskStore: LocalTaskStoring {
  private var loads: [CheckedContinuation<LocalTaskSnapshot, any Error>] = []
  private var mutations: [CheckedContinuation<LocalTaskSnapshot, any Error>] = []
  var loadCount: Int { loads.count }
  var mutationCount: Int { mutations.count }

  func load() async throws -> LocalTaskSnapshot {
    try await withCheckedThrowingContinuation { loads.append($0) }
  }

  func mutate(_ mutation: LocalTaskMutation) async throws -> LocalTaskSnapshot {
    try await withCheckedThrowingContinuation { mutations.append($0) }
  }

  func finishLoad(_ index: Int, result: Result<LocalTaskSnapshot, any Error>) {
    loads[index].resume(with: result)
  }

  func finishMutation(_ index: Int, result: Result<LocalTaskSnapshot, any Error>) {
    mutations[index].resume(with: result)
  }
}
