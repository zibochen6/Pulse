import Foundation
import XCTest

@testable import Pulse

@MainActor
final class LocalTaskInteractionStorageTests: XCTestCase {
  private func storageURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseInteractionStorage-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory.appendingPathComponent("tasks.json")
  }

  private func seed(_ document: LocalTaskDocument, at url: URL) throws -> Data {
    // Retain deliberately noncanonical formatting to verify the backup copies
    // source bytes, rather than decoding and encoding the legacy document.
    let bytes = Data("\n  ".utf8) + (try JSONEncoder().encode(document)) + Data("\n".utf8)
    try bytes.write(to: url, options: .atomic)
    return bytes
  }

  private func assertError(
    _ expected: LocalTaskStoreError,
    operation: () async throws -> LocalTaskSnapshot,
    file: StaticString = #filePath, line: UInt = #line
  ) async {
    do {
      _ = try await operation()
      XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
      XCTAssertEqual(error as? LocalTaskStoreError, expected, file: file, line: line)
    }
  }

  func testStandaloneTagRetryKeepsEmptyListAndRejectsMultipleDestinationsAtomically() async throws {
    let url = try storageURL()
    let store = LocalTaskStore(fileURL: url)
    let id = UUID()
    let created = try await store.mutate(.createTag(id: id, name: "  Work  ")).document
    XCTAssertEqual(created.tags, [TaskTag(id: id, name: "Work")])
    XCTAssertTrue(created.tasks.isEmpty)
    let bytes = try Data(contentsOf: url)
    let retried = try await store.mutate(.createTag(id: id, name: " work ")).document
    XCTAssertEqual(retried, created)
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    await assertError(.duplicateTag) {
      try await store.mutate(.createTag(id: UUID(), name: " WORK "))
    }
    await assertError(.reservedTag) {
      try await store.mutate(.createTag(id: UUID(), name: " ToDo "))
    }
    await assertError(.reservedTag) {
      try await store.mutate(.renameTag(id: id, name: "Todo"))
    }
    await assertError(.multipleLists) {
      try await store.mutate(
        .saveTask(id: nil, text: "Invalid", tagIDs: [id], newTagNames: ["New"]))
    }
    await assertError(.multipleLists) {
      try await store.mutate(
        .saveTask(id: nil, text: "Invalid", tagIDs: [], newTagNames: ["One", "Two"]))
    }
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  func testLegacyNormalizationUsesOriginalTagOrderAndBacksUpExactBytesOnce() async throws {
    let url = try storageURL()
    let work = TaskTag(name: "Work")
    let todo = TaskTag(name: " tOdO ")
    let home = TaskTag(name: "Home")
    let day = Calendar.current.startOfDay(for: Date())
    let original = LocalTaskDocument(
      tasks: [
        LocalTask(text: "Unclassified 1"), LocalTask(text: "Unclassified 2"),
        LocalTask(text: "Unclassified 3"), LocalTask(text: "Unclassified 4"),
        LocalTask(
          text: "First custom wins", completed: true, tagIDs: [home.id, work.id],
          repeatsDaily: true, lastCompletedDay: day),
        LocalTask(text: "Legacy Todo wins", tagIDs: [home.id, todo.id]),
        LocalTask(text: "Legacy Todo only", tagIDs: [todo.id]),
      ], tags: [work, todo, home])
    let bytes = try seed(original, at: url)
    let store = LocalTaskStore(fileURL: url)
    var expected = original
    expected.tags = [work, home]
    expected.tasks[4].tagIDs = [work.id]
    expected.tasks[5].tagIDs = []
    expected.tasks[6].tagIDs = []
    let normalized = try await store.load().document
    XCTAssertEqual(normalized, expected)
    XCTAssertEqual(normalized.tasks.filter { $0.tagIDs.isEmpty }.count, 6)
    XCTAssertEqual(try Data(contentsOf: store.compatibilityBackupURL), bytes)
    let normalizedBytes = try Data(contentsOf: url)
    // A writer that always fails proves a normalized reload writes neither
    // source nor backup. A harmless no-op mutation must likewise avoid writes.
    let readOnlyStore = LocalTaskStore(fileURL: url, writer: InteractionNoWriteWriter())
    let loaded = try await readOnlyStore.load().document
    let noOp = try await readOnlyStore.mutate(.deleteTask(UUID())).document
    XCTAssertEqual(loaded, expected)
    XCTAssertEqual(noOp, expected)
    XCTAssertEqual(try Data(contentsOf: url), normalizedBytes)
    XCTAssertEqual(try Data(contentsOf: store.compatibilityBackupURL), bytes)
  }

  func testBackupThrowNoOpAndWrongBytesNeverReplaceOriginal() async throws {
    for mode in InteractionBackupFaultWriter.Mode.allCases {
      let url = try storageURL()
      let todo = TaskTag(name: "Todo")
      let bytes = try seed(
        LocalTaskDocument(tasks: [LocalTask(text: "Keep", tagIDs: [todo.id])], tags: [todo]),
        at: url)
      let store = LocalTaskStore(fileURL: url, writer: InteractionBackupFaultWriter(mode: mode))
      await assertError(.backupFailed) { try await store.load() }
      XCTAssertEqual(try Data(contentsOf: url), bytes, "Backup fault: \(mode)")
    }
  }

  func testDifferentExistingBackupIsPreservedAndBlocksNormalization() async throws {
    let url = try storageURL()
    let todo = TaskTag(name: "Todo")
    let bytes = try seed(LocalTaskDocument(tags: [todo]), at: url)
    let store = LocalTaskStore(fileURL: url)
    let previousBackup = Data("previous original file".utf8)
    try previousBackup.write(to: store.compatibilityBackupURL)
    await assertError(.backupFailed) { try await store.load() }
    await assertError(.backupFailed) {
      try await store.mutate(.createTag(id: UUID(), name: "Work"))
    }
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertEqual(try Data(contentsOf: store.compatibilityBackupURL), previousBackup)
  }

  func testNormalizationCommittedBeforeVerificationFailureRecoversWithoutReplacingBackup()
    async throws
  {
    let url = try storageURL()
    let todo = TaskTag(name: "Todo")
    let task = LocalTask(text: "Recover", completed: true, tagIDs: [todo.id])
    let bytes = try seed(LocalTaskDocument(tasks: [task], tags: [todo]), at: url)
    let store = LocalTaskStore(fileURL: url, writer: InteractionNormalizationWriter())
    await assertError(.verificationFailed) { try await store.load() }
    XCTAssertEqual(try Data(contentsOf: store.compatibilityBackupURL), bytes)
    var expectedTask = task
    expectedTask.tagIDs = []
    let recovered = try await LocalTaskStore(fileURL: url).load().document
    XCTAssertEqual(recovered, LocalTaskDocument(tasks: [expectedTask]))
    XCTAssertEqual(try Data(contentsOf: store.compatibilityBackupURL), bytes)
    let sourceAfterRecovery = try Data(contentsOf: url)
    _ = try await store.load()
    XCTAssertEqual(try Data(contentsOf: url), sourceAfterRecovery)
  }

  func testDeleteReceiptUsesLatestTransactionAndUndoPreservesInterveningEdits() async throws {
    let url = try storageURL()
    let first = LocalTask(text: "First")
    let target = LocalTask(text: "Stale target")
    let last = LocalTask(text: "Last")
    _ = try seed(LocalTaskDocument(tasks: [first, target, last]), at: url)
    let store = LocalTaskStore(fileURL: url)
    let controller = LocalTaskController(store: store)
    await controller.refresh()
    let otherStore = LocalTaskStore(fileURL: url)
    _ = try await otherStore.mutate(.deleteTask(first.id))
    _ = try await otherStore.mutate(
      .saveTask(
        id: target.id, text: "Latest target", tagIDs: [], newTagNames: [], repeatsDaily: true))
    let completed = try await otherStore.mutate(
      .completeRepeating(taskID: target.id, completedAt: Date())
    ).document.tasks[0]
    let deleted = await controller.deleteTask(id: target.id)
    XCTAssertTrue(deleted)
    let receipt = try XCTUnwrap(controller.deletionHistory.last)
    XCTAssertEqual(receipt.task, completed)
    XCTAssertEqual(receipt.index, 0)
    XCTAssertNil(receipt.previousID)
    XCTAssertEqual(receipt.nextID, last.id)
    _ = try await otherStore.mutate(
      .saveTask(id: last.id, text: "Later edit survives", tagIDs: [], newTagNames: []))
    let restored = await controller.undoDeletion()
    XCTAssertTrue(restored)
    XCTAssertEqual(controller.document?.tasks.map(\.id), [target.id, last.id])
    XCTAssertEqual(controller.document?.tasks[0], completed)
    XCTAssertEqual(controller.document?.tasks[1].text, "Later edit survives")
  }

  func testRestoreFallsBackToTodoAndRejectsConflictingIDWithoutOverwriting() async throws {
    let url = try storageURL()
    let tag = TaskTag(name: "Work")
    let before = LocalTask(text: "Before")
    let target = LocalTask(text: "Deleted", completed: true, tagIDs: [tag.id])
    let after = LocalTask(text: "After")
    _ = try seed(LocalTaskDocument(tasks: [before, target, after], tags: [tag]), at: url)
    let store = LocalTaskStore(fileURL: url)
    let deleted = try await store.mutate(.deleteTask(target.id))
    let receipt = try XCTUnwrap(deleted.deletionReceipt)
    _ = try await store.mutate(.deleteTag(tag.id))
    _ = try await store.mutate(.deleteTask(after.id))
    let restored = try await store.mutate(.restoreTask(receipt)).document
    var untaggedTarget = target
    untaggedTarget.tagIDs = []
    XCTAssertEqual(restored.tasks, [before, untaggedTarget])
    XCTAssertTrue(restored.tags.isEmpty)
    let bytes = try Data(contentsOf: url)
    _ = try await store.mutate(.restoreTask(receipt))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    _ = try await store.mutate(
      .saveTask(id: target.id, text: "Newer contents", tagIDs: [], newTagNames: []))
    let conflictingBytes = try Data(contentsOf: url)
    await assertError(.taskConflict) { try await store.mutate(.restoreTask(receipt)) }
    XCTAssertEqual(try Data(contentsOf: url), conflictingBytes)
  }

  func testFailedDeleteWithConfirmedPresenceDoesNotDuplicateHistoryOnRetry() async throws {
    try await checkDeleteRetryHistory(fault: .noWrite, failReload: false)
  }

  func testFailedDeleteWithFailedReloadDoesNotDuplicateHistoryOnRetry() async throws {
    try await checkDeleteRetryHistory(fault: .noWrite, failReload: true)
  }

  func testCommittedDeleteWithFailedReloadIsRecoveredByRetryWithOneReceipt() async throws {
    try await checkDeleteRetryHistory(fault: .trailingWhitespace, failReload: true)
  }

  private func checkDeleteRetryHistory(
    fault: InteractionFaultStore.Fault, failReload: Bool
  ) async throws {
    let url = try storageURL()
    let task = LocalTask(text: "Delete once")
    _ = try seed(LocalTaskDocument(tasks: [task]), at: url)
    let store = InteractionFaultStore(
      fileURL: url, faults: [fault, .atomic], failReloadAfter: failReload ? [1] : [])
    let controller = LocalTaskController(store: store)
    await controller.refresh()
    _ = await controller.deleteTask(id: task.id)
    if fault == .noWrite { XCTAssertTrue(controller.deletionHistory.isEmpty) }
    let retried = await controller.deleteTask(id: task.id)
    XCTAssertTrue(retried)
    XCTAssertEqual(controller.document?.tasks, [])
    XCTAssertEqual(controller.deletionHistory.count, 1)
    XCTAssertEqual(controller.deletionHistory.first?.task, task)
    let restored = await controller.undoDeletion()
    XCTAssertTrue(restored)
    XCTAssertEqual(controller.document?.tasks, [task])
    XCTAssertTrue(controller.deletionHistory.isEmpty)
  }

  func testRestoreCommittedBeforeVerificationFailureRetainsReceiptAndRetriesWithoutDuplicate()
    async throws
  {
    let url = try storageURL()
    let task = LocalTask(text: "Restore once")
    _ = try seed(LocalTaskDocument(tasks: [task]), at: url)
    let store = InteractionFaultStore(
      fileURL: url, faults: [.atomic, .trailingWhitespace, .atomic])
    let controller = LocalTaskController(store: store)
    await controller.refresh()
    let deleted = await controller.deleteTask(id: task.id)
    XCTAssertTrue(deleted)
    let receipt = try XCTUnwrap(controller.deletionHistory.last)
    let firstRestore = await controller.undoDeletion()
    XCTAssertFalse(firstRestore)
    XCTAssertEqual(controller.document?.tasks, [task])
    XCTAssertEqual(controller.deletionHistory, [receipt])
    let retried = await controller.undoDeletion()
    XCTAssertTrue(retried)
    XCTAssertEqual(controller.document?.tasks, [task])
    XCTAssertTrue(controller.deletionHistory.isEmpty)
    let disk = try await LocalTaskStore(fileURL: url).load().document
    XCTAssertEqual(disk.tasks, [task])
  }

  func testHistoryKeepsLatestTwentyAndRestoresInOriginalRelativeOrder() async throws {
    let url = try storageURL()
    let tasks = (0..<22).map { LocalTask(text: "Task \($0)") }
    _ = try seed(LocalTaskDocument(tasks: tasks), at: url)
    let controller = LocalTaskController(store: LocalTaskStore(fileURL: url))
    await controller.refresh()
    for task in tasks {
      let deleted = await controller.deleteTask(id: task.id)
      XCTAssertTrue(deleted)
    }
    XCTAssertEqual(
      controller.deletionHistory.map { $0.task.id }, Array(tasks.dropFirst(2)).map(\.id))
    await controller.refresh()
    XCTAssertEqual(controller.deletionHistory.count, 20)
    for task in tasks.dropFirst(2).reversed() {
      XCTAssertEqual(controller.deletionHistory.last?.task.id, task.id)
      let restored = await controller.undoDeletion()
      XCTAssertTrue(restored)
    }
    XCTAssertEqual(controller.document?.tasks, Array(tasks.dropFirst(2)))
    XCTAssertTrue(controller.deletionHistory.isEmpty)
  }
}

private struct InteractionNoWriteWriter: LocalTaskFileWriting {
  func write(_ data: Data, to fileURL: URL) throws { throw LocalTaskStoreError.saveFailed }
}

private struct InteractionTrailingWhitespaceWriter: LocalTaskFileWriting {
  func write(_ data: Data, to fileURL: URL) throws {
    try (data + Data("\n".utf8)).write(to: fileURL, options: .atomic)
  }
}

private struct InteractionBackupFaultWriter: LocalTaskFileWriting {
  enum Mode: CaseIterable { case throwing, noOp, wrongBytes }
  let mode: Mode

  func write(_ data: Data, to fileURL: URL) throws {
    switch mode {
    case .throwing: throw LocalTaskStoreError.saveFailed
    case .noOp: return
    case .wrongBytes: try Data("wrong backup".utf8).write(to: fileURL, options: .atomic)
    }
  }
}

private struct InteractionNormalizationWriter: LocalTaskFileWriting {
  func write(_ data: Data, to fileURL: URL) throws {
    if fileURL.lastPathComponent == "tasks.json" {
      try (data + Data("\n".utf8)).write(to: fileURL, options: .atomic)
    } else {
      try data.write(to: fileURL, options: .atomic)
    }
  }
}

/// Choose a fault at each real storage transaction; keep all file behavior in
/// LocalTaskStore so the regression exercises actual receipts and verification.
private actor InteractionFaultStore: LocalTaskStoring {
  enum Fault: Sendable { case atomic, noWrite, trailingWhitespace }
  let fileURL: URL
  private var faults: [Fault]
  private let failReloadAfter: Set<Int>
  private var mutationCount = 0
  private var failedLoadsRemaining = 0

  init(fileURL: URL, faults: [Fault], failReloadAfter: Set<Int> = []) {
    self.fileURL = fileURL
    self.faults = faults
    self.failReloadAfter = failReloadAfter
  }

  func load() async throws -> LocalTaskSnapshot {
    if failedLoadsRemaining > 0 {
      failedLoadsRemaining -= 1
      throw LocalTaskStoreError.unreadable
    }
    return try await LocalTaskStore(fileURL: fileURL).load()
  }

  func mutate(_ mutation: LocalTaskMutation) async throws -> LocalTaskSnapshot {
    mutationCount += 1
    let fault = faults.isEmpty ? .atomic : faults.removeFirst()
    let writer: any LocalTaskFileWriting
    switch fault {
    case .atomic: writer = AtomicLocalTaskFileWriter()
    case .noWrite: writer = InteractionNoWriteWriter()
    case .trailingWhitespace: writer = InteractionTrailingWhitespaceWriter()
    }
    do {
      return try await LocalTaskStore(fileURL: fileURL, writer: writer).mutate(mutation)
    } catch {
      if failReloadAfter.contains(mutationCount) { failedLoadsRemaining += 1 }
      throw error
    }
  }
}
