import Foundation
import XCTest

@testable import Pulse

@MainActor
final class LocalTaskControllerTests: XCTestCase {
  private func store() throws -> LocalTaskStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseLocalController-\(UUID().uuidString)")
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

  func testCreateEditCompleteDeleteAndFilteringConfirmFromStorage() async throws {
    let store = try store()
    let controller = LocalTaskController(store: store)
    XCTAssertNil(controller.document)
    await controller.refresh()
    XCTAssertEqual(controller.document, LocalTaskDocument())
    let saved = await controller.saveTask(
      id: nil, text: "Tagged", tagIDs: [], newTagNames: ["Work", "Home"])
    XCTAssertTrue(saved)
    let tagged = try XCTUnwrap(controller.document?.tasks.first)
    let tags = try XCTUnwrap(controller.document?.tags)
    XCTAssertEqual(controller.tasks(matching: .tag(tags[0].id)), [tagged])
    XCTAssertEqual(controller.tasks(matching: .untagged), [])
    let created = await controller.saveTask(id: nil, text: "Untagged", tagIDs: [], newTagNames: [])
    XCTAssertTrue(created)
    XCTAssertEqual(controller.tasks(matching: .all).count, 2)
    XCTAssertEqual(controller.tasks(matching: .untagged).map(\.text), ["Untagged"])
    let completion = try XCTUnwrap(controller.setCompleted(true, taskID: tagged.id))
    await completion.value
    XCTAssertTrue(try XCTUnwrap(controller.document?.tasks.first).completed)
    XCTAssertEqual(controller.document?.tasks.first?.id, tagged.id)
    let edited = await controller.saveTask(
      id: tagged.id, text: "Updated", tagIDs: tagged.tagIDs, newTagNames: [])
    XCTAssertTrue(edited)
    XCTAssertTrue(try XCTUnwrap(controller.document?.tasks.first).completed)
    let renamed = await controller.renameTag(id: tags[0].id, name: "Job")
    XCTAssertTrue(renamed)
    let detached = await controller.deleteTag(id: tags[0].id)
    XCTAssertTrue(detached)
    XCTAssertEqual(controller.document?.tasks.first?.tagIDs, [tags[1].id])
    let deleted = await controller.deleteTask(id: tagged.id)
    XCTAssertTrue(deleted)
    let reopened = LocalTaskController(store: store)
    await reopened.refresh()
    XCTAssertEqual(reopened.document, controller.document)
    XCTAssertEqual(reopened.document?.tasks.map(\.text), ["Untagged"])
  }

  func testPendingRejectsDuplicateAndNeverPublishesBeforeSave() async throws {
    let original = LocalTaskDocument(tasks: [LocalTask(text: "One")])
    let storage = ControlledLocalTaskStore()
    let controller = LocalTaskController(store: storage)
    let loading = Task { await controller.refresh() }
    try await waitUntil { await storage.loadCount == 1 }
    XCTAssertTrue(controller.isLoading)
    await storage.finishLoad(0, result: .success(LocalTaskSnapshot(document: original)))
    await loading.value
    let id = original.tasks[0].id
    let saving = try XCTUnwrap(controller.setCompleted(true, taskID: id))
    XCTAssertTrue(controller.pendingTaskIDs.contains(id))
    XCTAssertTrue(controller.isSaving)
    XCTAssertNil(controller.setCompleted(true, taskID: id))
    XCTAssertEqual(controller.document, original)
    try await waitUntil { await storage.mutationCount == 1 }
    var confirmed = original
    confirmed.tasks[0].completed = true
    await storage.finishMutation(0, result: .success(LocalTaskSnapshot(document: confirmed)))
    await saving.value
    XCTAssertEqual(controller.document, confirmed)
    XCTAssertFalse(controller.isSaving)
    XCTAssertTrue(controller.pendingTaskIDs.isEmpty)
  }

  func testEarlierMutationReplyDoesNotReplaceLaterDiskObservation() async throws {
    let original = LocalTaskDocument(tasks: [LocalTask(text: "One"), LocalTask(text: "Two")])
    let storage = ControlledLocalTaskStore()
    let controller = LocalTaskController(store: storage)
    let loading = Task { await controller.refresh() }
    try await waitUntil { await storage.loadCount == 1 }
    await storage.finishLoad(0, result: .success(LocalTaskSnapshot(document: original)))
    await loading.value
    let one = try XCTUnwrap(controller.setCompleted(true, taskID: original.tasks[0].id))
    let two = try XCTUnwrap(controller.setCompleted(true, taskID: original.tasks[1].id))
    try await waitUntil { await storage.mutationCount == 2 }
    var first = original
    first.tasks[0].completed = true
    let early = LocalTaskSnapshot(document: first)
    var final = first
    final.tasks[1].completed = true
    let latest = LocalTaskSnapshot(document: final)
    await storage.finishMutation(1, result: .success(latest))
    await two.value
    XCTAssertTrue(controller.isSaving)
    await storage.finishMutation(0, result: .success(early))
    await one.value
    XCTAssertEqual(controller.document, final)
    XCTAssertFalse(controller.isSaving)
  }

  func testFailureShowsActualSnapshotAndAllowsExplicitRetry() async throws {
    let original = LocalTaskDocument(tasks: [LocalTask(text: "One")])
    let storage = ControlledLocalTaskStore()
    let controller = LocalTaskController(store: storage)
    let initial = Task { await controller.refresh() }
    try await waitUntil { await storage.loadCount == 1 }
    await storage.finishLoad(0, result: .success(LocalTaskSnapshot(document: original)))
    await initial.value
    let save = try XCTUnwrap(controller.setCompleted(true, taskID: original.tasks[0].id))
    try await waitUntil { await storage.mutationCount == 1 }
    await storage.finishMutation(0, result: .failure(LocalTaskStoreError.saveFailed))
    try await waitUntil { await storage.loadCount == 2 }
    await storage.finishLoad(1, result: .success(LocalTaskSnapshot(document: original)))
    await save.value
    XCTAssertEqual(controller.document, original)
    XCTAssertEqual(controller.completionFailures[original.tasks[0].id]?.completed, true)
    XCTAssertTrue(controller.pendingTaskIDs.isEmpty)
    let retry = try XCTUnwrap(controller.setCompleted(true, taskID: original.tasks[0].id))
    try await waitUntil { await storage.mutationCount == 2 }
    var confirmed = original
    confirmed.tasks[0].completed = true
    await storage.finishMutation(1, result: .success(LocalTaskSnapshot(document: confirmed)))
    await retry.value
    XCTAssertEqual(controller.document, confirmed)
    XCTAssertTrue(controller.completionFailures.isEmpty)
  }

  func testCorruptLoadCannotCreateBlankReplacementAndFailedSaveRetainsInputModel() async throws {
    let store = try store()
    let bytes = Data("{unreadable".utf8)
    try bytes.write(to: store.fileURL)
    let controller = LocalTaskController(store: store)
    await controller.refresh()
    XCTAssertNil(controller.document)
    XCTAssertNotNil(controller.errorMessage)
    let created = await controller.saveTask(
      id: nil, text: "Do not overwrite", tagIDs: [], newTagNames: [])
    XCTAssertFalse(created)
    XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
    try FileManager.default.removeItem(at: store.fileURL)
    await controller.refresh()
    XCTAssertEqual(controller.document, LocalTaskDocument())
    let saved = await controller.saveTask(id: nil, text: "Confirmed", tagIDs: [], newTagNames: [])
    XCTAssertTrue(saved)
    let original = controller.document
    let invalid = await controller.saveTask(id: nil, text: " \n", tagIDs: [], newTagNames: [])
    XCTAssertFalse(invalid)
    XCTAssertEqual(controller.document, original)
    XCTAssertNotNil(controller.errorMessage)
  }

  func testRefreshRetainsLoadedDocumentAndIgnoresOlderReadReply() async throws {
    let original = LocalTaskDocument(tasks: [LocalTask(text: "One")])
    let storage = ControlledLocalTaskStore()
    let controller = LocalTaskController(store: storage)
    let initial = Task { await controller.refresh() }
    try await waitUntil { await storage.loadCount == 1 }
    await storage.finishLoad(0, result: .success(LocalTaskSnapshot(document: original)))
    await initial.value
    let oldRead = LocalTaskSnapshot(document: original)
    let refresh = Task { await controller.refresh() }
    try await waitUntil { await storage.loadCount == 2 }
    XCTAssertEqual(controller.document, original)
    let saving = try XCTUnwrap(controller.setCompleted(true, taskID: original.tasks[0].id))
    try await waitUntil { await storage.mutationCount == 1 }
    var final = original
    final.tasks[0].completed = true
    await storage.finishMutation(0, result: .success(LocalTaskSnapshot(document: final)))
    await saving.value
    await storage.finishLoad(1, result: .success(oldRead))
    await refresh.value
    XCTAssertEqual(controller.document, final)
  }

  func testFailedCompletionRetainsItsOwnRetryWhenAnotherTaskSucceeds() async throws {
    let original = LocalTaskDocument(tasks: [LocalTask(text: "One"), LocalTask(text: "Two")])
    let storage = ControlledLocalTaskStore()
    let controller = LocalTaskController(store: storage)
    let initial = Task { await controller.refresh() }
    try await waitUntil { await storage.loadCount == 1 }
    await storage.finishLoad(0, result: .success(LocalTaskSnapshot(document: original)))
    await initial.value
    let one = try XCTUnwrap(controller.setCompleted(true, taskID: original.tasks[0].id))
    let two = try XCTUnwrap(controller.setCompleted(true, taskID: original.tasks[1].id))
    try await waitUntil { await storage.mutationCount == 2 }
    await storage.finishMutation(0, result: .failure(LocalTaskStoreError.saveFailed))
    try await waitUntil { await storage.loadCount == 2 }
    var secondConfirmed = original
    secondConfirmed.tasks[1].completed = true
    await storage.finishLoad(1, result: .success(LocalTaskSnapshot(document: secondConfirmed)))
    await one.value
    let failure = try XCTUnwrap(controller.completionFailures[original.tasks[0].id])
    XCTAssertEqual(failure.taskID, original.tasks[0].id)
    XCTAssertTrue(failure.completed)
    await storage.finishMutation(1, result: .success(LocalTaskSnapshot(document: secondConfirmed)))
    await two.value
    XCTAssertEqual(controller.completionFailures[original.tasks[0].id], failure)
    XCTAssertNil(controller.completionFailures[original.tasks[1].id])
    let retry = try XCTUnwrap(controller.setCompleted(failure.completed, taskID: failure.taskID))
    try await waitUntil { await storage.mutationCount == 3 }
    var final = secondConfirmed
    final.tasks[0].completed = true
    await storage.finishMutation(2, result: .success(LocalTaskSnapshot(document: final)))
    await retry.value
    XCTAssertTrue(controller.completionFailures.isEmpty)
    XCTAssertEqual(controller.document, final)
  }

  func testVerificationFailureCreationRetryUsesSameTaskAndTags() async throws {
    let baselineStore = try store()
    let store = LocalTaskStore(
      fileURL: baselineStore.fileURL, writer: TrailingWhitespaceLocalWriter())
    let controller = LocalTaskController(store: store)
    await controller.refresh()
    let creationID = UUID()
    let first = await controller.saveTask(
      id: nil, text: "Draft", tagIDs: [], newTagNames: ["Work"], creationID: creationID)
    XCTAssertFalse(first)
    XCTAssertEqual(controller.document?.tasks.map(\.id), [creationID])
    XCTAssertEqual(controller.document?.tags.map(\.name), ["Work"])
    XCTAssertNotNil(controller.errorMessage)
    let retry = await controller.saveTask(
      id: nil, text: "Draft", tagIDs: [], newTagNames: ["Work"], creationID: creationID)
    XCTAssertTrue(retry)
    XCTAssertEqual(controller.document?.tasks.map(\.id), [creationID])
    XCTAssertEqual(controller.document?.tags.count, 1)
    XCTAssertNil(controller.errorMessage)
    let divergent = await controller.saveTask(
      id: nil, text: "Changed draft", tagIDs: [], newTagNames: ["Work"], creationID: creationID)
    XCTAssertFalse(divergent)
    XCTAssertEqual(controller.document?.tasks.count, 1)
    XCTAssertEqual(controller.document?.tasks.first?.text, "Draft")
  }

  func testDeletionRetriesConfirmAlreadyPersistedTargetState() async throws {
    let baselineStore = try store()
    let original = try await baselineStore.mutate(
      .saveTask(id: nil, text: "Delete", tagIDs: [], newTagNames: ["Work"])
    ).document
    let store = LocalTaskStore(
      fileURL: baselineStore.fileURL, writer: TrailingWhitespaceLocalWriter())
    let controller = LocalTaskController(store: store)
    await controller.refresh()
    let deletedTag = await controller.deleteTag(id: original.tags[0].id)
    XCTAssertFalse(deletedTag)
    XCTAssertEqual(controller.document?.tags.count, 0)
    let retriedTag = await controller.deleteTag(id: original.tags[0].id)
    XCTAssertTrue(retriedTag)
    XCTAssertEqual(controller.document?.tasks.count, 1)
    let deletedTask = await controller.deleteTask(id: original.tasks[0].id)
    XCTAssertFalse(deletedTask)
    XCTAssertEqual(controller.document?.tasks.count, 0)
    let retriedTask = await controller.deleteTask(id: original.tasks[0].id)
    XCTAssertTrue(retriedTask)
    XCTAssertEqual(controller.document?.tasks.count, 0)
  }

  func testEditingWithNewTagCanRetryAfterVerificationFailureWithoutDuplicates() async throws {
    let baselineStore = try store()
    let original = try await baselineStore.mutate(
      .saveTask(id: nil, text: "Original", tagIDs: [], newTagNames: [])
    ).document
    let store = LocalTaskStore(
      fileURL: baselineStore.fileURL, writer: TrailingWhitespaceLocalWriter())
    let controller = LocalTaskController(store: store)
    await controller.refresh()
    let id = original.tasks[0].id
    let first = await controller.saveTask(id: id, text: "Edited", tagIDs: [], newTagNames: ["Work"])
    XCTAssertFalse(first)
    XCTAssertEqual(controller.document?.tasks.map(\.id), [id])
    XCTAssertEqual(controller.document?.tasks[0].text, "Edited")
    XCTAssertEqual(controller.document?.tags.count, 1)
    let second = await controller.saveTask(
      id: id, text: "Edited", tagIDs: [], newTagNames: ["Work"])
    XCTAssertTrue(second)
    XCTAssertEqual(controller.document?.tasks.map(\.id), [id])
    XCTAssertEqual(controller.document?.tags.map(\.name), ["Work"])
    XCTAssertNil(controller.errorMessage)
  }
}

private struct TrailingWhitespaceLocalWriter: LocalTaskFileWriting {
  func write(_ data: Data, to fileURL: URL) throws {
    // A valid but unexpected persisted document models a post-write validation
    // failure without accessing any real task configuration.
    try (data + Data("\n".utf8)).write(to: fileURL, options: .atomic)
  }
}

private actor ControlledLocalTaskStore: LocalTaskStoring {
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
