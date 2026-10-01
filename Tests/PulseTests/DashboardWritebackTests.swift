import Darwin
import Foundation
import XCTest

@testable import Pulse

final class DashboardWritebackTests: XCTestCase {
  private let parser = ApexDashboardParser()

  private func document(_ body: String) -> String {
    """
    ---
    dashboard: true
    columns:
      - name: Inbox
        color: "#123456"
        type: todo
    ---
    ## Inbox
    \(body)
    """
  }

  private func temporaryFile(_ data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseWriteback-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("dashboard.md")
    try data.write(to: url)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return url
  }

  private func expectError(_ expected: DashboardWriteError, operation: () async throws -> Void)
    async
  {
    do {
      try await operation()
      XCTFail("Expected \(expected)")
    } catch { XCTAssertEqual(error as? DashboardWriteError, expected) }
  }

  func testRoundTripPreservesEveryOtherByteAndNewlineStyle() async throws {
    for separator in ["\n", "\r\n"] {
      for hasBOM in [false, true] {
        for finalNewline in [false, true] {
          let text =
            document("### Card\n- [ ] 你好 🚀 #tag [[Link]] ^anchor\n- [x] Done\n- [X] Also done")
            .replacingOccurrences(of: "\n", with: separator) + (finalNewline ? separator : "")
          let original = (hasBOM ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(text.utf8)
          let url = try temporaryFile(original)
          let store = DashboardFileStore()
          var snapshot = try await store.load(fileURL: url)
          XCTAssertEqual(snapshot.allTasks.map(\.lineNumber), [10, 11, 12])
          let task = try XCTUnwrap(snapshot.allTasks.first)
          let offset = try XCTUnwrap(task.source?.stateByteOffset)
          snapshot = try await store.setCompleted(
            true, task: task, snapshot: snapshot, fileURL: url)
          var expected = original
          expected[offset] = 120
          XCTAssertEqual(try Data(contentsOf: url), expected)
          XCTAssertTrue(snapshot.allTasks[0].completed)
          snapshot = try await store.setCompleted(
            false, task: snapshot.allTasks[0], snapshot: snapshot, fileURL: url)
          XCTAssertEqual(try Data(contentsOf: url), original)
          XCTAssertFalse(snapshot.allTasks[0].completed)
          for index in [1, 2] {
            let selected = snapshot.allTasks[index]
            let before = try Data(contentsOf: url)
            _ = try await store.setCompleted(
              false, task: selected, snapshot: snapshot, fileURL: url)
            var expected = before
            expected[try XCTUnwrap(selected.source?.stateByteOffset)] = 32
            XCTAssertEqual(try Data(contentsOf: url), expected)
            snapshot = try await store.load(fileURL: url)
          }
        }
      }
    }
  }

  func testNoteLinksDoNotHideDashboardTasksOrBecomeWritableCheckboxes() async throws {
    let text = document(
      "### Tasks\n- [ ] Keep a fictional task\n### Notes\ntype: notes\n- [[Example/Note]]\n- [[Example/Other|Alias]]\n- [Documentation](https://example.com)\n- [x](https://example.com)"
    )
    let original = Data(text.utf8)
    let url = try temporaryFile(original)
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    XCTAssertEqual(snapshot.columns[0].cards.count, 2)
    XCTAssertEqual(snapshot.allTasks.count, 1)
    XCTAssertTrue(snapshot.columns[0].cards[1].tasks.isEmpty)
    let target = try XCTUnwrap(snapshot.allTasks.first)
    _ = try await store.setCompleted(true, task: target, snapshot: snapshot, fileURL: url)
    var expected = original
    expected[try XCTUnwrap(target.source?.stateByteOffset)] = 120
    XCTAssertEqual(try Data(contentsOf: url), expected)
    for malformed in ["- [ ]", "- [xx] Broken", "  - [ ] Wrong indent"] {
      XCTAssertThrowsError(
        try parser.parse(contents: document("### Card\n" + malformed), fileURL: url))
    }
  }

  func testDuplicateTasksChangeOnlySelectedOccurrence() async throws {
    let original = Data(
      document(
        "### Card\nid: repeated\n- [ ] Same\n- [ ] Same\n### Other\nid: repeated\n- [ ] Same"
      ).utf8)
    let url = try temporaryFile(original)
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    let selected = snapshot.allTasks[1]
    let result = try await store.setCompleted(
      true, task: selected, snapshot: snapshot, fileURL: url)
    XCTAssertEqual(result.allTasks.map(\.completed), [false, true, false])
    var expected = original
    expected[try XCTUnwrap(selected.source?.stateByteOffset)] = 120
    XCTAssertEqual(try Data(contentsOf: url), expected)
    XCTAssertEqual(Set(snapshot.allTasks.map(\.id)).count, 3)
    XCTAssertEqual(Set(snapshot.columns[0].cards.map(\.id)).count, 2)
  }

  func testVerifiedMetadataNestedTasksAndCodeExamples() async throws {
    let fixture = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "sample-apex-writeback", withExtension: "md"))
    let original = try Data(contentsOf: fixture)
    let url = try temporaryFile(original)
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    XCTAssertEqual(snapshot.allTasks.count, 6)
    XCTAssertEqual(snapshot.allTasks[1].source?.indentation, 4)
    XCTAssertEqual(snapshot.allTasks[1].source?.ancestors.count, 1)
    XCTAssertEqual(snapshot.allTasks[0].blockIdentifier, "sample-anchor")
    let target = snapshot.allTasks[1]
    let result = try await store.setCompleted(false, task: target, snapshot: snapshot, fileURL: url)
    var expected = original
    expected[try XCTUnwrap(target.source?.stateByteOffset)] = 32
    XCTAssertEqual(try Data(contentsOf: url), expected)
    XCTAssertFalse(result.allTasks[1].completed)
    XCTAssertFalse(result.allTasks[0].completed)  // No parent/child cascade.
    XCTAssertFalse(snapshot.allTasks[4].canToggle)
    await expectError(.unsupportedState) {
      _ = try await store.setCompleted(
        true, task: snapshot.allTasks[4], snapshot: snapshot, fileURL: url)
    }
    XCTAssertEqual(try Data(contentsOf: url), expected)
  }

  func testExternalInsertAndDeleteBeforeTargetRelocateUniqueContext() async throws {
    for insertion in [true, false] {
      let body = "### Other\n- [ ] Unrelated\n### Target\nid: target\ncontext\n- [ ] Chosen\nafter"
      let text = document(body)
      let original =
        insertion ? text : text.replacingOccurrences(of: "### Other", with: "extra\n### Other")
      let url = try temporaryFile(Data(original.utf8))
      let store = DashboardFileStore()
      let snapshot = try await store.load(fileURL: url)
      let selected = snapshot.allTasks[1]
      let changed =
        insertion ? original.replacingOccurrences(of: "### Other", with: "extra\n### Other") : text
      try Data(changed.utf8).write(to: url)
      let result = try await store.setCompleted(
        true, task: selected, snapshot: snapshot, fileURL: url)
      XCTAssertTrue(result.allTasks[1].completed)
      XCTAssertEqual(
        try String(contentsOf: url, encoding: .utf8),
        changed.replacingOccurrences(of: "- [ ] Chosen", with: "- [x] Chosen"))
    }
  }

  func testUniqueBlockAnchorSurvivesAdjacentExternalInsertion() async throws {
    let text = document("### Card\n- [ ] Chosen ^unique\nafter")
    let url = try temporaryFile(Data(text.utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    let changed = text.replacingOccurrences(of: "- [ ] Chosen", with: "inserted\n- [ ] Chosen")
    try Data(changed.utf8).write(to: url)
    let result = try await store.setCompleted(
      true, task: snapshot.allTasks[0], snapshot: snapshot, fileURL: url)
    XCTAssertTrue(result.allTasks[0].completed)
  }

  func testExternalAmbiguityDeletionAndContentChangesNeverWrite() async throws {
    let cases: [(String, String)] = [
      ("### Card\n- [ ] Same\n- [ ] Same", "### Card\nextra\n- [ ] Same\n- [ ] Same"),
      ("### Card\n- [ ] Chosen\nafter", "### Card\n- [ ] Changed\nafter"),
      ("### Card\n- [ ] Chosen\nafter", "### Card\nafter"),
      ("### Card\n- [ ] Chosen\nafter", "### Card\ninserted\n- [ ] Chosen\nafter"),
      (
        "### Card\n- [ ] Chosen ^duplicate\n- [ ] Other ^duplicate",
        "### Card\ninserted\n- [ ] Chosen ^duplicate\n- [ ] Other ^duplicate"
      ),
      ("### Card\n- [ ] Chosen\nafter", "### Card\n- [-] Chosen\nafter"),
    ]
    for (before, after) in cases {
      let url = try temporaryFile(Data(document(before).utf8))
      let store = DashboardFileStore()
      let snapshot = try await store.load(fileURL: url)
      let changed = Data(document(after).utf8)
      try changed.write(to: url)
      await expectError(.conflict) {
        _ = try await store.setCompleted(
          true, task: snapshot.allTasks[0], snapshot: snapshot, fileURL: url)
      }
      XCTAssertEqual(try Data(contentsOf: url), changed)
    }
  }

  func testExternalAlreadyCompletedIsIdempotentWithoutWriting() async throws {
    let text = document("### Card\n- [ ] Chosen")
    let url = try temporaryFile(Data(text.utf8))
    let snapshot = try await DashboardFileStore().load(fileURL: url)
    let changed = Data(text.replacingOccurrences(of: "[ ]", with: "[X]").utf8)
    try changed.write(to: url)
    let result = try await DashboardFileStore(writer: FailingByteWriter()).setCompleted(
      true, task: snapshot.allTasks[0], snapshot: snapshot, fileURL: url)
    XCTAssertTrue(result.allTasks[0].completed)
    XCTAssertEqual(try Data(contentsOf: url), changed)
  }

  func testConcurrentTasksInOneFileDoNotLoseEarlierWrites() async throws {
    let url = try temporaryFile(Data(document("### Card\n- [ ] One\n- [ ] Two").utf8))
    let firstStore = DashboardFileStore()
    let secondStore = DashboardFileStore()
    let snapshot = try await firstStore.load(fileURL: url)
    async let one = firstStore.setCompleted(
      true, task: snapshot.allTasks[0], snapshot: snapshot, fileURL: url)
    async let two = secondStore.setCompleted(
      true, task: snapshot.allTasks[1], snapshot: snapshot, fileURL: url)
    _ = try await (one, two)
    let refreshed = try await firstStore.load(fileURL: url)
    XCTAssertEqual(refreshed.allTasks.map(\.completed), [true, true])
    let merged = refreshed.preservingIdentities(from: snapshot)
    XCTAssertEqual(merged.allTasks.map(\.id), snapshot.allTasks.map(\.id))
  }

  func testReadonlyAndDeletedFilesReportUsefulErrors() async throws {
    let url = try temporaryFile(Data(document("### Card\n- [ ] Chosen").utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
    await expectError(.permissionDenied) {
      _ = try await store.setCompleted(
        true, task: snapshot.allTasks[0], snapshot: snapshot, fileURL: url)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    try FileManager.default.removeItem(at: url)
    await expectError(.fileMissing) { _ = try await store.load(fileURL: url) }
    await expectError(.fileMissing) {
      _ = try await store.setCompleted(
        true, task: snapshot.allTasks[0], snapshot: snapshot, fileURL: url)
    }
  }

  func testUnsupportedEncodingMalformedIndentationAndUnclosedFenceAreRejected() async throws {
    let url = try temporaryFile(Data([0xFF, 0xFE, 0x41, 0]))
    await expectError(.unsupportedEncoding) {
      _ = try await DashboardFileStore().load(fileURL: url)
    }
    for body in [
      "### Card\n  - [ ] Two spaces", "### Card\n    - [ ] Orphan", "### Card\n```\n- [ ] Example",
    ] {
      XCTAssertThrowsError(try parser.parse(contents: document(body), fileURL: url))
    }
  }

  func testSaveAndPostWriteVerificationFailureNeverRollBackExternalContent() async throws {
    let original = Data(document("### Card\n- [ ] Chosen").utf8)
    let url = try temporaryFile(original)
    let snapshot = try await DashboardFileStore().load(fileURL: url)
    await expectError(.saveFailed) {
      _ = try await DashboardFileStore(writer: FailingByteWriter()).setCompleted(
        true, task: snapshot.allTasks[0], snapshot: snapshot, fileURL: url)
    }
    XCTAssertEqual(try Data(contentsOf: url), original)
    await expectError(.verificationFailed) {
      _ = try await DashboardFileStore(writer: ExternalEditByteWriter()).setCompleted(
        true, task: snapshot.allTasks[0], snapshot: snapshot, fileURL: url)
    }
    let after = try Data(contentsOf: url)
    XCTAssertNotEqual(after, original)
    XCTAssertEqual(after.last, 33)  // The external append must not be overwritten by a rollback.
  }
}

private struct FailingByteWriter: DashboardByteWriting {
  func write(descriptor: Int32, byte: UInt8, offset: Int) throws {
    throw DashboardWriteError.saveFailed
  }
}

private struct ExternalEditByteWriter: DashboardByteWriting {
  func write(descriptor: Int32, byte: UInt8, offset: Int) throws {
    try DashboardPOSIXByteWriter().write(descriptor: descriptor, byte: byte, offset: offset)
    var info = stat()
    guard fstat(descriptor, &info) == 0 else { throw DashboardWriteError.saveFailed }
    var externalByte: UInt8 = 33
    guard pwrite(descriptor, &externalByte, 1, info.st_size) == 1 else {
      throw DashboardWriteError.saveFailed
    }
  }
}
