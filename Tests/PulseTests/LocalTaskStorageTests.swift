import Foundation
import XCTest

@testable import Pulse

final class LocalTaskStorageTests: XCTestCase {
  private func storageURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseLocalTasks-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory.appendingPathComponent("tasks.json")
  }

  private func assertStoreError(
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

  func testFreshStoreReadsEmptyWithoutWriting() async throws {
    let url = try storageURL()
    let document = try await LocalTaskStore(fileURL: url).load().document
    XCTAssertEqual(document, LocalTaskDocument())
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testTaskLifecyclePersistsOrderIdentityAndMultipleTagsAcrossReload() async throws {
    let url = try storageURL()
    let store = LocalTaskStore(fileURL: url)
    var document = try await store.mutate(
      .saveTask(id: nil, text: "  调研 🧭\n第二行  ", tagIDs: [], newTagNames: [" 工作 ", "个人"])
    ).document
    let first = try XCTUnwrap(document.tasks.first)
    XCTAssertEqual(first.text, "调研 🧭\n第二行")
    XCTAssertEqual(document.tags.map(\.name), ["工作", "个人"])
    XCTAssertEqual(first.tagIDs, Set(document.tags.map(\.id)))
    let last = try await store.mutate(
      .saveTask(id: nil, text: "Second", tagIDs: [], newTagNames: [])
    ).document
    let order = last.tasks.map(\.id)
    document = try await store.mutate(.setCompleted(taskID: first.id, completed: true)).document
    XCTAssertTrue(document.tasks[0].completed)
    XCTAssertEqual(document.tasks.map(\.id), order)
    document = try await LocalTaskStore(fileURL: url).load().document
    XCTAssertTrue(document.tasks[0].completed)
    document = try await store.mutate(.setCompleted(taskID: first.id, completed: false)).document
    XCTAssertFalse(document.tasks[0].completed)
    document = try await store.mutate(
      .saveTask(id: first.id, text: "Edited", tagIDs: first.tagIDs, newTagNames: [])
    ).document
    XCTAssertEqual(document.tasks[0].text, "Edited")
    XCTAssertEqual(document.tasks.map(\.id), order)
    document = try await store.mutate(.deleteTask(first.id)).document
    XCTAssertEqual(document.tasks.map(\.id), [order[1]])
    let restored = try await LocalTaskStore(fileURL: url).load().document
    XCTAssertEqual(restored, document)
    let bytes = try Data(contentsOf: url)
    let disk = try JSONDecoder().decode(LocalTaskDocument.self, from: bytes)
    XCTAssertEqual(disk.schemaVersion, 1)
    XCTAssertEqual(disk, restored)
  }

  func testInvalidTagTransactionDoesNotPartiallyAddTagsOrTasks() async throws {
    let url = try storageURL()
    let store = LocalTaskStore(fileURL: url)
    _ = try await store.mutate(
      .saveTask(id: nil, text: "Existing", tagIDs: [], newTagNames: ["Work"]))
    let original = try Data(contentsOf: url)
    await assertStoreError(.duplicateTag) {
      try await store.mutate(
        .saveTask(id: nil, text: "No partial save", tagIDs: [], newTagNames: ["New", " work "]))
    }
    XCTAssertEqual(try Data(contentsOf: url), original)
    await assertStoreError(.duplicateTag) {
      try await store.mutate(
        .saveTask(id: nil, text: "No partial save", tagIDs: [], newTagNames: ["Tag", "TAG"]))
    }
    await assertStoreError(.emptyTag) {
      try await store.mutate(
        .saveTask(id: nil, text: "No partial save", tagIDs: [], newTagNames: ["New", " \n"]))
    }
    await assertStoreError(.emptyTask) {
      try await store.mutate(.saveTask(id: nil, text: " \n", tagIDs: [], newTagNames: []))
    }
    await assertStoreError(.tagMissing) {
      try await store.mutate(.saveTask(id: nil, text: "Task", tagIDs: [UUID()], newTagNames: []))
    }
    XCTAssertEqual(try Data(contentsOf: url), original)
  }

  func testTagRenameAndDeleteKeepTasksAndOnlyDetachAssociations() async throws {
    let store = LocalTaskStore(fileURL: try storageURL())
    var document = try await store.mutate(
      .saveTask(id: nil, text: "Tagged", tagIDs: [], newTagNames: ["Work", "Home"])
    ).document
    let task = document.tasks[0]
    let work = document.tags[0]
    let home = document.tags[1]
    _ = try await store.mutate(.setCompleted(taskID: task.id, completed: true))
    await assertStoreError(.duplicateTag) {
      try await store.mutate(.renameTag(id: work.id, name: " HOME "))
    }
    document = try await store.mutate(.renameTag(id: work.id, name: " Job ")).document
    XCTAssertEqual(document.tags[0], TaskTag(id: work.id, name: "Job"))
    document = try await store.mutate(.deleteTag(work.id)).document
    XCTAssertEqual(document.tasks.map(\.id), [task.id])
    XCTAssertTrue(document.tasks[0].completed)
    XCTAssertEqual(document.tasks[0].tagIDs, [home.id])
    XCTAssertEqual(document.tags, [home])
    document = try await store.mutate(.deleteTag(home.id)).document
    XCTAssertEqual(document.tasks[0].tagIDs, [])
    XCTAssertEqual(document.tasks[0].text, "Tagged")
  }

  func testConcurrentStoresSerializeAndDoNotLosePriorMutations() async throws {
    let url = try storageURL()
    let first = LocalTaskStore(fileURL: url)
    let second = LocalTaskStore(fileURL: url)
    async let addedOne = first.mutate(.saveTask(id: nil, text: "One", tagIDs: [], newTagNames: []))
    async let addedTwo = second.mutate(.saveTask(id: nil, text: "Two", tagIDs: [], newTagNames: []))
    _ = try await (addedOne, addedTwo)
    let tasks = try await first.load().document.tasks
    XCTAssertEqual(Set(tasks.map(\.text)), ["One", "Two"])
    async let completedOne = first.mutate(.setCompleted(taskID: tasks[0].id, completed: true))
    async let completedTwo = second.mutate(.setCompleted(taskID: tasks[1].id, completed: true))
    _ = try await (completedOne, completedTwo)
    let final = try await first.load().document
    XCTAssertEqual(final.tasks.map(\.id), tasks.map(\.id))
    XCTAssertTrue(final.tasks.allSatisfy(\.completed))
  }

  func testCorruptionAndUnsupportedVersionArePreservedAndCannotBeOverwritten() async throws {
    let url = try storageURL()
    let store = LocalTaskStore(fileURL: url)
    let corrupt = Data("{broken".utf8)
    try corrupt.write(to: url)
    await assertStoreError(.corruptDocument) { try await store.load() }
    await assertStoreError(.corruptDocument) {
      try await store.mutate(.saveTask(id: nil, text: "Would erase", tagIDs: [], newTagNames: []))
    }
    XCTAssertEqual(try Data(contentsOf: url), corrupt)
    let future = try JSONEncoder().encode(LocalTaskDocument(schemaVersion: 99))
    try future.write(to: url)
    await assertStoreError(.unsupportedVersion) { try await store.load() }
    await assertStoreError(.unsupportedVersion) {
      try await store.mutate(.saveTask(id: nil, text: "Would erase", tagIDs: [], newTagNames: []))
    }
    XCTAssertEqual(try Data(contentsOf: url), future)
    let dangling = try JSONEncoder().encode(
      LocalTaskDocument(tasks: [LocalTask(text: "Task", tagIDs: [UUID()])]))
    try dangling.write(to: url)
    await assertStoreError(.corruptDocument) { try await store.load() }
    XCTAssertEqual(try Data(contentsOf: url), dangling)
  }

  func testReadOnlyAndWriteFailuresKeepConfirmedFile() async throws {
    let url = try storageURL()
    let baseline = try await LocalTaskStore(fileURL: url).mutate(
      .saveTask(id: nil, text: "Keep", tagIDs: [], newTagNames: [])
    ).document
    let original = try Data(contentsOf: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
    await assertStoreError(.saveFailed) {
      try await LocalTaskStore(fileURL: url).mutate(
        .setCompleted(taskID: baseline.tasks[0].id, completed: true))
    }
    XCTAssertEqual(try Data(contentsOf: url), original)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    let failing = LocalTaskStore(fileURL: url, writer: FailingLocalWriter())
    await assertStoreError(.saveFailed) {
      try await failing.mutate(.setCompleted(taskID: baseline.tasks[0].id, completed: true))
    }
    XCTAssertEqual(try Data(contentsOf: url), original)
    let silent = LocalTaskStore(fileURL: url, writer: NoopLocalWriter())
    await assertStoreError(.verificationFailed) {
      try await silent.mutate(.setCompleted(taskID: baseline.tasks[0].id, completed: true))
    }
    XCTAssertEqual(try Data(contentsOf: url), original)
  }

  func testStaleTaskAndTagIDsAreRejectedWithoutMutation() async throws {
    let url = try storageURL()
    let store = LocalTaskStore(fileURL: url)
    _ = try await store.mutate(.saveTask(id: nil, text: "Keep", tagIDs: [], newTagNames: []))
    let original = try Data(contentsOf: url)
    await assertStoreError(.taskMissing) {
      try await store.mutate(
        .saveTask(id: UUID(), text: "Missing", tagIDs: [], newTagNames: ["No partial tag"]))
    }
    await assertStoreError(.taskMissing) {
      try await store.mutate(.setCompleted(taskID: UUID(), completed: true))
    }
    await assertStoreError(.tagMissing) {
      try await store.mutate(.renameTag(id: UUID(), name: "Missing"))
    }
    _ = try await store.mutate(.deleteTask(UUID()))
    _ = try await store.mutate(.deleteTag(UUID()))
    XCTAssertEqual(try Data(contentsOf: url), original)
  }
}

private struct FailingLocalWriter: LocalTaskFileWriting {
  func write(_ data: Data, to fileURL: URL) throws { throw CocoaError(.fileWriteNoPermission) }
}

private struct NoopLocalWriter: LocalTaskFileWriting {
  func write(_ data: Data, to fileURL: URL) throws {}
}
