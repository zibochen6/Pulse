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

  func testTaskLifecyclePersistsOrderIdentityAndSingleTagAcrossReload() async throws {
    let url = try storageURL()
    let store = LocalTaskStore(fileURL: url)
    var document = try await store.mutate(
      .saveTask(id: nil, text: "  调研 🧭\n第二行  ", tagIDs: [], newTagNames: [" 工作 "])
    ).document
    let first = try XCTUnwrap(document.tasks.first)
    XCTAssertEqual(first.text, "调研 🧭\n第二行")
    XCTAssertEqual(document.tags.map(\.name), ["工作"])
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
        .saveTask(id: nil, text: "No partial save", tagIDs: [], newTagNames: [" work "]))
    }
    XCTAssertEqual(try Data(contentsOf: url), original)
    await assertStoreError(.multipleLists) {
      try await store.mutate(
        .saveTask(id: nil, text: "No partial save", tagIDs: [], newTagNames: ["Tag", "TAG"]))
    }
    await assertStoreError(.emptyTag) {
      try await store.mutate(
        .saveTask(id: nil, text: "No partial save", tagIDs: [], newTagNames: [" \n"]))
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
      .saveTask(id: nil, text: "Tagged", tagIDs: [], newTagNames: ["Work"])
    ).document
    let task = document.tasks[0]
    let work = document.tags[0]
    let home = TaskTag(name: "Home")
    _ = try await store.mutate(.createTag(id: home.id, name: home.name))
    _ = try await store.mutate(.setCompleted(taskID: task.id, completed: true))
    await assertStoreError(.duplicateTag) {
      try await store.mutate(.renameTag(id: work.id, name: " HOME "))
    }
    document = try await store.mutate(.renameTag(id: work.id, name: " Job ")).document
    XCTAssertEqual(document.tags[0], TaskTag(id: work.id, name: "Job"))
    document = try await store.mutate(.deleteTag(work.id)).document
    XCTAssertEqual(document.tasks.map(\.id), [task.id])
    XCTAssertTrue(document.tasks[0].completed)
    XCTAssertEqual(document.tasks[0].tagIDs, [])
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

  func testPreRepeatFormatLoadsAndRoundTripsWithinSchemaVersionOne() async throws {
    // A literal file from the build that predates repeating tasks: neither new
    // key exists, so decoding must fall back to non-repeating defaults.
    let legacy = """
      {
        "schemaVersion" : 1,
        "tags" : [
          { "id" : "11111111-1111-1111-1111-111111111111", "name" : "Work" }
        ],
        "tasks" : [
          {
            "completed" : false,
            "id" : "22222222-2222-2222-2222-222222222222",
            "tagIDs" : ["11111111-1111-1111-1111-111111111111"],
            "text" : "Legacy"
          }
        ]
      }
      """
    let url = try storageURL()
    try Data(legacy.utf8).write(to: url)
    let loaded = try await LocalTaskStore(fileURL: url).load().document
    XCTAssertEqual(loaded.schemaVersion, 1)
    XCTAssertEqual(loaded.tasks.map(\.text), ["Legacy"])
    XCTAssertFalse(loaded.tasks[0].repeatsDaily)
    XCTAssertNil(loaded.tasks[0].lastCompletedDay)
    let reencoded = try JSONEncoder().encode(loaded)
    let roundTripped = try JSONDecoder().decode(LocalTaskDocument.self, from: reencoded)
    XCTAssertEqual(roundTripped, loaded)
    XCTAssertEqual(roundTripped.schemaVersion, 1)
  }

  func testRepeatingFieldsPersistAcrossReloadAndEncodeIdentically() async throws {
    let url = try storageURL()
    let store = LocalTaskStore(fileURL: url)
    let created = try await store.mutate(
      .saveTask(id: nil, text: "Daily", tagIDs: [], newTagNames: [], repeatsDaily: true)
    ).document
    let id = try XCTUnwrap(created.tasks.first).id
    XCTAssertTrue(created.tasks[0].repeatsDaily)
    let day = try XCTUnwrap(
      Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 9)))
    var completed = try await store.mutate(.completeRepeating(taskID: id, completedAt: day))
      .document
    XCTAssertTrue(completed.tasks[0].completed)
    XCTAssertEqual(completed.tasks[0].lastCompletedDay, Calendar.current.startOfDay(for: day))
    completed = try await LocalTaskStore(fileURL: url).load().document
    XCTAssertTrue(completed.tasks[0].repeatsDaily)
    XCTAssertEqual(completed.tasks[0].lastCompletedDay, Calendar.current.startOfDay(for: day))
    // Equal documents must serialize to equal bytes; otherwise the store's
    // byte-for-byte verification would report spurious failures.
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var copy = completed
    copy.tasks[0].lastCompletedDay = try XCTUnwrap(completed.tasks[0].lastCompletedDay)
    XCTAssertEqual(copy, completed)
    XCTAssertEqual(try encoder.encode(completed), try encoder.encode(copy))
    XCTAssertEqual(try encoder.encode(completed), try encoder.encode(completed))
    // The day is written as fixed UTC whole-second ISO8601, not a raw Double.
    XCTAssertTrue(String(decoding: try encoder.encode(completed), as: UTF8.self).contains("T"))
  }

  func testCompleteRepeatingIsIdempotentWithinADayAndReArmsOnTheNext() async throws {
    let url = try storageURL()
    let store = LocalTaskStore(fileURL: url)
    let document = try await store.mutate(
      .saveTask(id: nil, text: "Daily", tagIDs: [], newTagNames: [], repeatsDaily: true)
    ).document
    let id = document.tasks[0].id
    let today = try XCTUnwrap(
      Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()))
    let yesterdaysTask = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: today))
    var snapshot = try await store.mutate(.completeRepeating(taskID: id, completedAt: today))
    XCTAssertTrue(snapshot.document.tasks[0].completed)
    XCTAssertEqual(
      snapshot.document.tasks[0].lastCompletedDay, Calendar.current.startOfDay(for: today))
    let afterFirst = snapshot.document
    let bytes = try Data(contentsOf: url)
    // Re-completing on the same day changes nothing, not even the file.
    snapshot = try await store.mutate(
      .completeRepeating(taskID: id, completedAt: today.addingTimeInterval(3_600)))
    XCTAssertEqual(snapshot.document, afterFirst)
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    // A completion from before today is re-completed with the new day recorded.
    snapshot = try await store.mutate(
      .completeRepeating(taskID: id, completedAt: yesterdaysTask))
    XCTAssertTrue(snapshot.document.tasks[0].completed)
    XCTAssertEqual(
      snapshot.document.tasks[0].lastCompletedDay,
      Calendar.current.startOfDay(for: yesterdaysTask))
  }

  func testCompleteRepeatingRejectsMissingAndNonRepeatingTasks() async throws {
    let url = try storageURL()
    let store = LocalTaskStore(fileURL: url)
    let document = try await store.mutate(
      .saveTask(id: nil, text: "Plain", tagIDs: [], newTagNames: [])
    ).document
    let id = document.tasks[0].id
    let bytes = try Data(contentsOf: url)
    await assertStoreError(.taskMissing) {
      try await store.mutate(.completeRepeating(taskID: UUID(), completedAt: Date()))
    }
    await assertStoreError(.taskNotRepeating) {
      try await store.mutate(.completeRepeating(taskID: id, completedAt: Date()))
    }
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  func testResetRepeatingTasksClearsOnlyEarlierCompletionsAndIsIdempotent() async throws {
    let url = try storageURL()
    let store = LocalTaskStore(fileURL: url)
    var document = try await store.mutate(
      .saveTask(id: nil, text: "Stale", tagIDs: [], newTagNames: [], repeatsDaily: true)
    ).document
    document = try await store.mutate(
      .saveTask(id: nil, text: "Today", tagIDs: [], newTagNames: [], repeatsDaily: true)
    ).document
    document = try await store.mutate(
      .saveTask(id: nil, text: "Plain", tagIDs: [], newTagNames: [])
    ).document
    let stale = document.tasks[0].id
    let todayTask = document.tasks[1].id
    let plain = document.tasks[2].id
    let today = try XCTUnwrap(
      Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()))
    let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: today))
    document = try await store.mutate(
      .completeRepeating(taskID: stale, completedAt: yesterday)
    ).document
    document = try await store.mutate(
      .completeRepeating(taskID: todayTask, completedAt: today)
    ).document
    document = try await store.mutate(.setCompleted(taskID: plain, completed: true)).document
    XCTAssertTrue(document.tasks.allSatisfy(\.completed))

    document = try await store.mutate(.resetRepeatingTasks(today: today)).document
    XCTAssertEqual(document.tasks.map(\.completed), [false, true, true])
    XCTAssertEqual(document.tasks.map(\.id), [stale, todayTask, plain])
    // The last completion day stays recorded so the task remembers when it ran.
    XCTAssertEqual(
      document.tasks[0].lastCompletedDay, Calendar.current.startOfDay(for: yesterday))
    let bytes = try Data(contentsOf: url)
    // Running again on the same day is a no-op, so a popover open is free.
    let repeated = try await store.mutate(.resetRepeatingTasks(today: today))
    XCTAssertEqual(repeated.document, document)
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  func testResetRepeatingTasksClearsCompletedTaskWithUnknownDay() async throws {
    let url = try storageURL()
    let store = LocalTaskStore(fileURL: url)
    // A completed daily task without a recorded day can only come from an
    // older file; it is treated as stale so it re-arms for the current day.
    let document = LocalTaskDocument(tasks: [
      LocalTask(text: "Unknown day", completed: true, repeatsDaily: true)
    ])
    try JSONEncoder().encode(document).write(to: url)
    let reset = try await store.mutate(.resetRepeatingTasks(today: Date())).document
    XCTAssertFalse(reset.tasks[0].completed)
    XCTAssertTrue(reset.tasks[0].repeatsDaily)
  }

  func testEditingRepeatFlagPersistsItAndClearsStaleDayWhenDisabled() async throws {
    let url = try storageURL()
    let store = LocalTaskStore(fileURL: url)
    var document = try await store.mutate(
      .saveTask(id: nil, text: "Task", tagIDs: [], newTagNames: [], repeatsDaily: true)
    ).document
    let id = document.tasks[0].id
    document = try await store.mutate(
      .completeRepeating(taskID: id, completedAt: Date())
    ).document
    XCTAssertTrue(document.tasks[0].completed)
    // Turning repetition off clears the day but keeps the user's completion.
    document = try await store.mutate(
      .saveTask(id: id, text: "Task", tagIDs: [], newTagNames: [], repeatsDaily: false)
    ).document
    XCTAssertFalse(document.tasks[0].repeatsDaily)
    XCTAssertTrue(document.tasks[0].completed)
    XCTAssertNil(document.tasks[0].lastCompletedDay)
    // Turning it back on keeps completion untouched and writes no new day.
    document = try await store.mutate(
      .saveTask(id: id, text: "Task", tagIDs: [], newTagNames: [], repeatsDaily: true)
    ).document
    XCTAssertTrue(document.tasks[0].repeatsDaily)
    XCTAssertTrue(document.tasks[0].completed)
    XCTAssertNil(document.tasks[0].lastCompletedDay)
  }

  func testRepeatToggledCreationRetryAfterVerificationFailureConfirmsSameTask() async throws {
    let url = try storageURL()
    let creationID = UUID()
    let store = LocalTaskStore(fileURL: url, writer: TrailingWhitespaceLocalWriter())
    await assertStoreError(.verificationFailed) {
      try await store.mutate(
        .saveTask(
          id: nil, text: "Draft", tagIDs: [], newTagNames: ["Work"], repeatsDaily: true,
          creationID: creationID))
    }
    // The write committed; only verification failed. Replaying the same draft
    // must confirm it (not append a duplicate) and keep the repeat flag.
    let confirmed = try await store.mutate(
      .saveTask(
        id: nil, text: "Draft", tagIDs: [], newTagNames: ["Work"], repeatsDaily: true,
        creationID: creationID)
    ).document
    XCTAssertEqual(confirmed.tasks.map(\.id), [creationID])
    XCTAssertTrue(confirmed.tasks[0].repeatsDaily)
    XCTAssertEqual(confirmed.tags.count, 1)
    // A creation retry whose repeat flag differs is a different draft, not a
    // replay; it must be rejected instead of silently rewriting the task.
    await assertStoreError(.taskConflict) {
      try await store.mutate(
        .saveTask(
          id: nil, text: "Draft", tagIDs: [], newTagNames: ["Work"], repeatsDaily: false,
          creationID: creationID))
    }
    let unchanged = try await LocalTaskStore(fileURL: url).load().document
    XCTAssertTrue(unchanged.tasks[0].repeatsDaily)
    XCTAssertEqual(unchanged.tasks.map(\.id), [creationID])
  }
}

private struct FailingLocalWriter: LocalTaskFileWriting {
  func write(_ data: Data, to fileURL: URL) throws { throw CocoaError(.fileWriteNoPermission) }
}

private struct NoopLocalWriter: LocalTaskFileWriting {
  func write(_ data: Data, to fileURL: URL) throws {}
}

private struct TrailingWhitespaceLocalWriter: LocalTaskFileWriting {
  func write(_ data: Data, to fileURL: URL) throws {
    // A valid but unexpected persisted document models a post-write validation
    // failure without accessing any real task configuration.
    try (data + Data("\n".utf8)).write(to: fileURL, options: .atomic)
  }
}
