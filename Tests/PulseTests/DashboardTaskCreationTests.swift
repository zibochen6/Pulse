import Darwin
import Foundation
import XCTest

@testable import Pulse

final class DashboardTaskCreationTests: XCTestCase {
  private func document(_ body: String) -> String {
    """
    ---
    dashboard: true
    columns:
      - name: 待办
        color: "#123456"
        type: todo
      - name: Notes
        color: "#654321"
        type: notes
    ---
    ## 待办
    \(body)
    """
  }

  private func temporaryFile(_ data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseCreation-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("dashboard.md")
    try data.write(to: url)
    addTeardownBlock {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: directory.path)
      try? FileManager.default.removeItem(at: directory)
    }
    return url
  }

  private func request(
    _ snapshot: Dashboard, column: Int = 0, card: Int = 0, text: String = "新增测试 🚀 👩‍💻 #fictional"
  ) -> DashboardTaskCreationRequest {
    DashboardTaskCreationRequest(
      text: text,
      destination: DashboardTaskDestination(
        column: snapshot.columns[column], card: snapshot.columns[column].cards[card]),
      snapshot: snapshot)
  }

  private func expectError(_ expected: DashboardWriteError, operation: () async throws -> Void)
    async
  {
    do {
      try await operation()
      XCTFail("Expected \(expected)")
    } catch {
      XCTAssertEqual(error as? DashboardWriteError, expected)
    }
  }

  func testInsertionPreservesBOMNewlinesFinalNewlineAndEveryOriginalByte() async throws {
    for newline in ["\n", "\r\n"] {
      for bom in [false, true] {
        for finalNewline in [false, true] {
          let body =
            "### Card\nid: existing\ntype: task\n- [ ] Older [[Link]]\n## Notes\n### Empty\ntype: notes"
          let text =
            document(body).replacingOccurrences(of: "\n", with: newline)
            + (finalNewline ? newline : "")
          let original = (bom ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(text.utf8)
          let url = try temporaryFile(original)
          let store = DashboardFileStore()
          let snapshot = try await store.load(fileURL: url)
          let intent = request(snapshot, column: 1)
          let result = try await store.addTask(request: intent, fileURL: url)
          let newRow =
            "- [ ] \(intent.text)\(newline)<!-- pulse-task-id: \(intent.creationIdentifier) -->"
          let expectedText =
            text + (finalNewline ? "" : newline) + newRow
            + (finalNewline ? newline : "")
          let expected = (bom ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(expectedText.utf8)
          XCTAssertEqual(try Data(contentsOf: url), expected)
          let storedLines = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            .components(separatedBy: newline)
          let checkboxLine = try XCTUnwrap(
            storedLines.first(where: { $0 == "- [ ] \(intent.text)" }))
          XCTAssertFalse(checkboxLine.contains("pulse-task-id"))
          XCTAssertEqual(result.allTasks.count, 2)
          XCTAssertFalse(result.allTasks[1].completed)
          XCTAssertNil(result.allTasks[1].blockIdentifier)
          XCTAssertEqual(result.allTasks[1].pulseCreationIdentifier, intent.creationIdentifier)
          XCTAssertEqual(result.allTasks[0].id, snapshot.allTasks[0].id)
          let restored = try await DashboardFileStore().load(fileURL: url)
          XCTAssertEqual(restored.allTasks[1].text, intent.text)
        }
      }
    }
  }

  func testSelectedDuplicateCardAndRepeatedRowsKeepIdentityAndOtherCards() async throws {
    let url = try temporaryFile(
      Data(document("### Card\n- [ ] Same\n- [ ] Same\n### Card\n- [ ] Same\n## Notes").utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    let intent = request(snapshot, card: 0)
    let result = try await store.addTask(request: intent, fileURL: url)
    XCTAssertEqual(result.columns[0].cards.map { $0.tasks.count }, [3, 1])
    XCTAssertEqual(
      result.allTasks.filter { $0.pulseCreationIdentifier != intent.creationIdentifier }.map(\.id),
      snapshot.allTasks.map(\.id))
    XCTAssertEqual(result.columns[0].cards[1].tasks[0].text, "Same")
    let repeated = try await store.addTask(request: intent, fileURL: url)
    XCTAssertEqual(repeated.allTasks.count, 4)
  }

  func testNestedTasksMetadataAndFencedExamplesStayUnchanged() async throws {
    let text = document(
      "### Card\nid: stable\ntype: task\n- [ ] Parent ^parent\n    - [X] Child 🧪 #tag\n```md\n### Not a destination\n- [ ] Not a task\n```\n\n## Notes"
    )
    let url = try temporaryFile(Data(text.utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    let intent = request(snapshot)
    let result = try await store.addTask(request: intent, fileURL: url)
    XCTAssertEqual(result.allTasks.count, 3)
    XCTAssertEqual(result.allTasks[1].source?.indentation, 4)
    XCTAssertEqual(result.allTasks[2].source?.indentation, 0)
    XCTAssertEqual(
      try String(contentsOf: url, encoding: .utf8),
      text.replacingOccurrences(
        of: "```\n\n## Notes",
        with:
          "```\n- [ ] \(intent.text)\n<!-- pulse-task-id: \(intent.creationIdentifier) -->\n\n## Notes"
      ))
  }

  func testUniqueDestinationRelocatesAndPreservesExternalEdits() async throws {
    let original = document("### Card\nid: stable\n- [ ] Old\n## Notes\n### Other")
    let url = try temporaryFile(Data(original.utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    let intent = request(snapshot)
    let changed = original.replacingOccurrences(of: "- [ ] Old", with: "external note\n- [X] Old")
      .replacingOccurrences(of: "## Notes", with: "### New other card\n- [ ] External\n## Notes")
    try Data(changed.utf8).write(to: url)
    let result = try await store.addTask(request: intent, fileURL: url)
    XCTAssertEqual(result.columns[0].cards.map { $0.tasks.count }, [2, 1])
    XCTAssertTrue(result.allTasks[0].completed)
    XCTAssertEqual(
      try String(contentsOf: url, encoding: .utf8),
      changed.replacingOccurrences(
        of: "### New other card",
        with:
          "- [ ] \(intent.text)\n<!-- pulse-task-id: \(intent.creationIdentifier) -->\n### New other card"
      ))
  }

  func testChangedDuplicateDeletedOrRenamedCardRefusesWithoutWriting() async throws {
    for body in [
      "### Card\n- [ ] Same\n### Card\n- [ ] Same\n## Notes",
      "### Card\nid: stable\n- [ ] Old\n## Notes",
    ] {
      let original = document(body)
      let changes =
        body.contains("stable")
        ? [
          original.replacingOccurrences(of: "### Card", with: "### Changed"),
          original.replacingOccurrences(of: "id: stable", with: "id: changed"),
          document("## Notes"),
        ] : [original.replacingOccurrences(of: "## Notes", with: "extra\n## Notes")]
      for changed in changes {
        let url = try temporaryFile(Data(original.utf8))
        let store = DashboardFileStore()
        let snapshot = try await store.load(fileURL: url)
        let intent = request(snapshot)
        try Data(changed.utf8).write(to: url)
        await expectError(.conflict) { _ = try await store.addTask(request: intent, fileURL: url) }
        XCTAssertEqual(try Data(contentsOf: url), Data(changed.utf8))
      }
    }
  }

  func testUncertainSaveRetryIsIdempotentAndEditedRetryCannotDuplicate() async throws {
    let url = try temporaryFile(Data(document("### Card\n- [ ] Old\n## Notes").utf8))
    let store = DashboardFileStore(replacer: FailingAfterCreationReplacer())
    let snapshot = try await store.load(fileURL: url)
    let intent = request(snapshot)
    await expectError(.saveFailed) { _ = try await store.addTask(request: intent, fileURL: url) }
    let persisted = try Data(contentsOf: url)
    let normal = DashboardFileStore(replacer: NeverCreationReplacer())
    let recovered = try await normal.addTask(request: intent, fileURL: url)
    XCTAssertEqual(recovered.allTasks.count, 2)
    XCTAssertEqual(try Data(contentsOf: url), persisted)
    let changed = DashboardTaskCreationRequest(
      id: intent.id, text: "Changed draft", destination: intent.destination, snapshot: snapshot)
    await expectError(.conflict) { _ = try await normal.addTask(request: changed, fileURL: url) }
    XCTAssertEqual(try Data(contentsOf: url), persisted)
  }

  func testCreatedTaskCanBeRelocatedAfterExternalLineInsertion() async throws {
    let url = try temporaryFile(Data(document("### Card\n- [ ] Existing\n## Notes").utf8))
    let store = DashboardFileStore()
    let original = try await store.load(fileURL: url)
    let intent = request(original)
    let created = try await store.addTask(request: intent, fileURL: url)
    let beforeExternalEdit = try String(contentsOf: url, encoding: .utf8)
    let withInsertedLine = beforeExternalEdit.replacingOccurrences(
      of: "### Card\n", with: "### Card\nExternal note\n")
    try Data(withInsertedLine.utf8).write(to: url)

    let target = try XCTUnwrap(
      created.allTasks.first(where: { $0.pulseCreationIdentifier == intent.creationIdentifier }))
    let completed = try await store.setCompleted(
      true, task: target, snapshot: created, fileURL: url)
    XCTAssertTrue(
      try XCTUnwrap(
        completed.allTasks.first(where: { $0.pulseCreationIdentifier == intent.creationIdentifier })
      ).completed)
    XCTAssertTrue(
      try String(contentsOf: url, encoding: .utf8).contains(
        "<!-- pulse-task-id: \(intent.creationIdentifier) -->"))
  }

  func testExternalChangeDuringStagingIsNotOverwritten() async throws {
    let original = document("### Card\n- [ ] Old\n## Notes")
    let changed = original.replacingOccurrences(of: "- [ ] Old", with: "- [ ] Edited externally")
    let url = try temporaryFile(Data(original.utf8))
    let store = DashboardFileStore(
      replacer: ExternallyChangingCreationReplacer(data: Data(changed.utf8)))
    let snapshot = try await store.load(fileURL: url)
    await expectError(.conflict) {
      _ = try await store.addTask(request: self.request(snapshot), fileURL: url)
    }
    XCTAssertEqual(try Data(contentsOf: url), Data(changed.utf8))
  }

  func testVerificationFailureRetainsExternalEditAndRetryFindsPersistedTask() async throws {
    let url = try temporaryFile(Data(document("### Card\n- [ ] Old\n## Notes").utf8))
    let store = DashboardFileStore(replacer: ChangingAfterCreationReplacer())
    let snapshot = try await store.load(fileURL: url)
    let intent = request(snapshot)
    await expectError(.verificationFailed) {
      _ = try await store.addTask(request: intent, fileURL: url)
    }
    let changed = try Data(contentsOf: url)
    XCTAssertTrue(String(decoding: changed, as: UTF8.self).contains("external verification note"))
    let retry = try await DashboardFileStore(replacer: NeverCreationReplacer()).addTask(
      request: intent, fileURL: url)
    XCTAssertEqual(retry.allTasks.count, 2)
    XCTAssertEqual(try Data(contentsOf: url), changed)
  }

  func testInvalidMultilineBlankOrControlCharacterTaskDoesNotWrite() async throws {
    let original = Data(document("### Card\n## Notes").utf8)
    let url = try temporaryFile(original)
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    for text in [" ", "Task\n## Notes", "Task\rOther", "Task\u{0000}", "Task\u{2028}Other"] {
      await expectError(.invalidTaskText) {
        _ = try await store.addTask(request: self.request(snapshot, text: text), fileURL: url)
      }
      XCTAssertEqual(try Data(contentsOf: url), original)
    }
  }

  func testMissingMovedReadOnlyAndUnwritableParentFailWithoutChanges() async throws {
    let original = Data(document("### Card\n- [ ] Old\n## Notes").utf8)
    for readonlyParent in [false, true] {
      let url = try temporaryFile(original)
      let store = DashboardFileStore()
      let snapshot = try await store.load(fileURL: url)
      let target = readonlyParent ? url.deletingLastPathComponent() : url
      try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: target.path)
      await expectError(.permissionDenied) {
        _ = try await store.addTask(request: self.request(snapshot), fileURL: url)
      }
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path)
      XCTAssertEqual(try Data(contentsOf: url), original)
    }
    let url = try temporaryFile(original)
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    let moved = url.deletingLastPathComponent().appendingPathComponent("moved.md")
    try FileManager.default.moveItem(at: url, to: moved)
    await expectError(.fileMissing) {
      _ = try await store.addTask(request: self.request(snapshot), fileURL: url)
    }
    XCTAssertEqual(try Data(contentsOf: moved), original)
  }

  func testDuplicatePulseCreationIdentifierDoesNotPickOneTask() async throws {
    let url = try temporaryFile(Data(document("### Card\n## Notes").utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    let intent = request(snapshot)
    let repeated = "- [ ] \(intent.text)\n<!-- pulse-task-id: \(intent.creationIdentifier) -->"
    let changed = Data(document("### Card\n\(repeated)\n\(repeated)\n## Notes").utf8)
    try changed.write(to: url)
    await expectError(.conflict) { _ = try await store.addTask(request: intent, fileURL: url) }
    XCTAssertEqual(try Data(contentsOf: url), changed)
  }

  func testUntrustedRequestMarkersKeepTasksVisibleButRefuseRetry() async throws {
    let original = document("### Card\n- [ ] Old\n## Notes")
    for variant in 0..<6 {
      let url = try temporaryFile(Data(original.utf8))
      let store = DashboardFileStore(replacer: NeverCreationReplacer())
      let snapshot = try await store.load(fileURL: url)
      let intent = request(snapshot)
      let marker = "<!-- pulse-task-id: \(intent.creationIdentifier) -->"
      let rows: String
      switch variant {
      case 0: rows = marker + "\n- [ ] \(intent.text)"
      case 1: rows = "- [ ] \(intent.text)\n\n" + marker
      case 2:
        rows = "- [ ] \(intent.text)\n<!-- pulse-task-id: \(intent.creationIdentifier) extra -->"
      case 3: rows = "- [ ] \(intent.text)\n" + marker + "\n- [ ] Other\n" + marker
      case 4: rows = "- [ ] \(intent.text)\n" + marker.uppercased()
      default: rows = "- [ ] \(intent.text)\n" + marker + "\n" + marker
      }
      let changed = Data(document("### Card\n\(rows)\n## Notes").utf8)
      try changed.write(to: url)
      let loaded = try await store.load(fileURL: url)
      XCTAssertFalse(loaded.allTasks.isEmpty)
      await expectError(.conflict) { _ = try await store.addTask(request: intent, fileURL: url) }
      XCTAssertEqual(try Data(contentsOf: url), changed)
    }
  }

  func testUnrelatedDetachedMarkerAllowsFreshCreation() async throws {
    let text = document(
      "### Card\n<!-- pulse-task-id: pulse-12345678-1234-1234-1234-123456789abc -->\n- [ ] Old\n## Notes"
    )
    let url = try temporaryFile(Data(text.utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    let intent = request(snapshot)
    let created = try await store.addTask(request: intent, fileURL: url)
    XCTAssertEqual(created.allTasks.map(\.text), ["Old", intent.text])
    let retried = try await store.addTask(request: intent, fileURL: url)
    XCTAssertEqual(retried.allTasks.count, 2)
  }

  func testOriginalUntrustedRequestIDRefusesWithoutWriting() async throws {
    let id = UUID()
    let marker = "<!-- pulse-task-id: pulse-\(id.uuidString.lowercased()) -->"
    let original = Data(document("### Card\n\(marker)\n- [ ] Old\n## Notes").utf8)
    let url = try temporaryFile(original)
    let store = DashboardFileStore(replacer: NeverCreationReplacer())
    let snapshot = try await store.load(fileURL: url)
    let intent = DashboardTaskCreationRequest(
      id: id, text: "New", destination: request(snapshot).destination, snapshot: snapshot)
    await expectError(.conflict) { _ = try await store.addTask(request: intent, fileURL: url) }
    XCTAssertEqual(try Data(contentsOf: url), original)
  }

  func testIdenticalCreationRetriesNeedExactAdditionalRowProof() async throws {
    let url = try temporaryFile(Data(document("### Card\n- [ ] Same\n## Notes").utf8))
    let store = DashboardFileStore()
    let original = try await store.load(fileURL: url)
    let intent = request(original, text: "Same")
    let created = try await store.addTask(request: intent, fileURL: url)
    XCTAssertEqual(created.allTasks.map(\.text), ["Same", "Same"])
    let retried = try await DashboardFileStore(replacer: NeverCreationReplacer())
      .addTask(request: intent, fileURL: url)
    XCTAssertEqual(retried.allTasks.count, 2)

    let marker = "<!-- pulse-task-id: \(intent.creationIdentifier) -->"
    let changed = Data(document("### Card\n- [ ] Same\n\(marker)\n## Notes").utf8)
    try changed.write(to: url)
    let reloaded = try await store.load(fileURL: url)
    XCTAssertEqual(reloaded.allTasks.count, 1)
    await expectError(.conflict) { _ = try await store.addTask(request: intent, fileURL: url) }
    XCTAssertEqual(try Data(contentsOf: url), changed)
  }

  func testDifferentConcurrentCreationRequestsPreserveBothRows() async throws {
    let url = try temporaryFile(Data(document("### Card\nid: unique\n- [ ] Old\n## Notes").utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    let one = request(snapshot, text: "One")
    let two = request(snapshot, text: "Two")
    async let first = store.addTask(request: one, fileURL: url)
    async let second = store.addTask(request: two, fileURL: url)
    _ = try await (first, second)
    let result = try await store.load(fileURL: url)
    XCTAssertEqual(Set(result.allTasks.map(\.text)), ["Old", "One", "Two"])
    XCTAssertEqual(
      Set(result.allTasks.compactMap(\.pulseCreationIdentifier)),
      [one.creationIdentifier, two.creationIdentifier])
  }

  func testOwnVerifiedInsertionChainKeepsQueuedLastDuplicateCheckboxSafe() async throws {
    let url = try temporaryFile(
      Data(document("### Card\n- [ ] Same\n- [ ] Same\n## Notes").utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    let intent = request(snapshot)
    _ = try await store.addTask(request: intent, fileURL: url)
    let result = try await store.setCompleted(
      true, task: snapshot.allTasks[1], snapshot: snapshot, fileURL: url)
    XCTAssertEqual(result.allTasks.map(\.completed), [false, true, false])
    XCTAssertEqual(result.allTasks[2].pulseCreationIdentifier, intent.creationIdentifier)
    _ = try await store.addTask(request: request(snapshot, text: "Next"), fileURL: url)
    let second = try await store.setCompleted(
      false, task: snapshot.allTasks[1], snapshot: snapshot, fileURL: url)
    XCTAssertEqual(second.allTasks.map(\.completed), [false, false, false, false])
  }

  func testExternalEditInvalidatesOwnInsertionProofInsteadOfRelaxingLocator() async throws {
    let url = try temporaryFile(
      Data(document("### Card\n- [ ] Same\n- [ ] Same\n## Notes").utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    _ = try await store.addTask(request: request(snapshot), fileURL: url)
    let before = try String(contentsOf: url, encoding: .utf8)
    let changed = Data(before.replacingOccurrences(of: "### Card", with: "external\n### Card").utf8)
    try changed.write(to: url)
    await expectError(.conflict) {
      _ = try await store.setCompleted(
        true, task: snapshot.allTasks[1], snapshot: snapshot, fileURL: url)
    }
    XCTAssertEqual(try Data(contentsOf: url), changed)
  }

  func testConcurrentCheckboxAndCreationDoNotLoseEitherOperation() async throws {
    let url = try temporaryFile(Data(document("### Card\n- [ ] Last\n## Notes").utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    let creation = request(snapshot)
    async let adding = store.addTask(request: creation, fileURL: url)
    async let checking = store.setCompleted(
      true, task: snapshot.allTasks[0], snapshot: snapshot, fileURL: url)
    _ = try await (adding, checking)
    let result = try await store.load(fileURL: url)
    XCTAssertEqual(result.allTasks.map(\.completed), [true, false])
  }

  func testInsertionHistoryIsBoundedAndOldAmbiguousIntentSafelyRefuses() async throws {
    let url = try temporaryFile(
      Data(document("### Card\n- [ ] Same\n- [ ] Same\n## Notes").utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    for index in 0..<17 {
      _ = try await store.addTask(request: request(snapshot, text: "Added \(index)"), fileURL: url)
    }
    let bytes = try Data(contentsOf: url)
    await expectError(.conflict) {
      _ = try await store.setCompleted(
        true, task: snapshot.allTasks[1], snapshot: snapshot, fileURL: url)
    }
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  func testNativeReplacementPreservesPermissionsAndExtendedAttributes() async throws {
    let url = try temporaryFile(Data(document("### Card\n## Notes").utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
    let value = Data("fictional metadata".utf8)
    let attribute = "dev.zibochen.pulse.creation-test"
    let installed = value.withUnsafeBytes {
      setxattr(url.path, attribute, $0.baseAddress, $0.count, 0, 0)
    }
    try XCTSkipUnless(installed == 0, "Temporary filesystem does not support extended attributes")
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    _ = try await store.addTask(request: request(snapshot), fileURL: url)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
    var readBack = Data(count: value.count)
    let count = readBack.withUnsafeMutableBytes {
      getxattr(url.path, attribute, $0.baseAddress, $0.count, 0, 0)
    }
    XCTAssertEqual(count, value.count)
    XCTAssertEqual(readBack, value)
  }

  func testUnsupportedEncodingAfterExternalReplacementDoesNotWrite() async throws {
    let text = document("### Card\n## Notes")
    let url = try temporaryFile(Data(text.utf8))
    let store = DashboardFileStore()
    let snapshot = try await store.load(fileURL: url)
    let utf16 = try XCTUnwrap(text.data(using: .utf16))
    try utf16.write(to: url)
    await expectError(.unsupportedEncoding) {
      _ = try await store.addTask(request: self.request(snapshot), fileURL: url)
    }
    XCTAssertEqual(try Data(contentsOf: url), utf16)
  }
}

private struct NeverCreationReplacer: DashboardDocumentReplacing {
  func replace(data: Data, fileURL: URL, validateBeforeReplacing: () throws -> Void) throws {
    XCTFail("An idempotent retry must not replace the file")
    throw DashboardWriteError.saveFailed
  }
}

private struct FailingAfterCreationReplacer: DashboardDocumentReplacing {
  func replace(data: Data, fileURL: URL, validateBeforeReplacing: () throws -> Void) throws {
    try DashboardAtomicDocumentReplacer().replace(
      data: data, fileURL: fileURL, validateBeforeReplacing: validateBeforeReplacing)
    throw DashboardWriteError.saveFailed
  }
}

private struct ExternallyChangingCreationReplacer: DashboardDocumentReplacing {
  let data: Data
  func replace(data: Data, fileURL: URL, validateBeforeReplacing: () throws -> Void) throws {
    try self.data.write(to: fileURL)
    try validateBeforeReplacing()
    XCTFail("The changed original must fail revision validation")
  }
}

private struct ChangingAfterCreationReplacer: DashboardDocumentReplacing {
  func replace(data: Data, fileURL: URL, validateBeforeReplacing: () throws -> Void) throws {
    try DashboardAtomicDocumentReplacer().replace(
      data: data, fileURL: fileURL, validateBeforeReplacing: validateBeforeReplacing)
    var changed = data
    changed.append(Data("\nexternal verification note".utf8))
    try changed.write(to: fileURL)
  }
}
