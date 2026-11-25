import AppKit
import Foundation
import XCTest

@testable import Pulse

@MainActor
final class QuickCopyTests: XCTestCase {
  func testCRUDAndSearchPreserveIDsAndSavedOrder() async throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("quick-copy.json")
    let controller = QuickCopyController(fileURL: fileURL) { _ in
      XCTFail("Storage operations must not write to the clipboard")
      return false
    }
    await controller.loadIfNeeded()
    XCTAssertTrue(controller.hasLoaded)
    XCTAssertTrue(controller.entries.isEmpty)

    let first = try await add("  Café prompt  ", text: "first", to: controller)
    let second = try await add("Meeting", text: "cafe is only in the body", to: controller)
    let third = try await add("CAFE notes", text: "  \t\n", to: controller)
    XCTAssertEqual(controller.entries.map(\.id), [first, second, third])
    XCTAssertEqual(controller.entries.first?.name, "Café prompt")
    XCTAssertEqual(controller.filteredEntries(matching: "  cafe ").map(\.id), [first, third])
    XCTAssertEqual(controller.filteredEntries(matching: "only in the body"), [])
    XCTAssertEqual(controller.filteredEntries(matching: "  ").map(\.id), [first, second, third])

    controller.beginEditing(second)
    controller.setDraftName("Discard me", for: second)
    XCTAssertTrue(controller.hasUnsavedEdits)
    controller.discardDraft()
    XCTAssertEqual(controller.entries[1].name, "Meeting")

    controller.beginEditing(second)
    controller.setDraftName("Follow-up", for: second)
    let saved = await controller.saveDraft()
    XCTAssertTrue(saved)
    let deleted = await controller.deleteEntry(first)
    XCTAssertTrue(deleted)
    XCTAssertFalse(controller.hasPendingWrite)

    let relaunched = QuickCopyController(fileURL: fileURL) { _ in false }
    await relaunched.loadIfNeeded()
    XCTAssertEqual(relaunched.entries.map(\.id), [second, third])
    XCTAssertEqual(relaunched.entries.map(\.name), ["Follow-up", "CAFE notes"])
    XCTAssertEqual(relaunched.entries.last?.text, "  \t\n")
    let document = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
    XCTAssertEqual(document["schemaVersion"] as? Int, 1)
  }

  func testNativeClipboardPreservesUnicodeSpacingAndLineEndingsAcrossRestart() async throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("quick-copy.json")
    let pasteboard = NSPasteboard(name: .init("PulseQuickCopyTests.\(UUID())"))
    defer { pasteboard.releaseGlobally() }
    XCTAssertTrue(QuickCopyController.write("sentinel", to: pasteboard))
    let text = "\t 提示词\r\n\nprintf 'Caf\u{E9}'  \n🧪 end \t\n"
    let decomposed = text.replacingOccurrences(of: "\u{E9}", with: "e\u{301}")
    XCTAssertEqual(text, decomposed)
    XCTAssertNotEqual(Array(text.utf8), Array(decomposed.utf8))

    let controller = QuickCopyController(fileURL: fileURL) {
      QuickCopyController.write($0, to: pasteboard)
    }
    await controller.loadIfNeeded()
    let id = try await add("Command", text: text, to: controller)
    controller.beginEditing(id)
    controller.setDraftText(decomposed, for: id)
    XCTAssertTrue(controller.hasUnsavedEdits)
    let saved = await controller.saveDraft()
    XCTAssertTrue(saved)
    XCTAssertEqual(pasteboard.string(forType: .string), "sentinel")

    let relaunched = QuickCopyController(fileURL: fileURL) {
      QuickCopyController.write($0, to: pasteboard)
    }
    await relaunched.loadIfNeeded()
    XCTAssertNil(relaunched.copiedEntryID)
    XCTAssertTrue(relaunched.copy(id))
    XCTAssertEqual(relaunched.copiedEntryID, id)
    let actual = try XCTUnwrap(pasteboard.string(forType: .string))
    XCTAssertEqual(Array(actual.utf8), Array(decomposed.utf8))
    XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
    XCTAssertEqual(pasteboard.pasteboardItems?.first?.types, [.string])
    relaunched.clearCopyFeedback()
  }

  func testWriteFailureKeepsDraftAndPublishedValueUntilRetry() async throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("storage")
    let fileURL = storage.appendingPathComponent("quick-copy.json")
    let heldStorage = directory.appendingPathComponent("held", isDirectory: true)
    let controller = QuickCopyController(fileURL: fileURL) { _ in false }
    await controller.loadIfNeeded()
    let id = try await add("Original", text: "old body", to: controller)
    let savedBytes = try Data(contentsOf: fileURL)

    try FileManager.default.moveItem(at: storage, to: heldStorage)
    try Data().write(to: storage)
    controller.beginEditing(id)
    controller.setDraftName("Updated", for: id)
    controller.setDraftText("new body\n", for: id)
    let failed = await controller.saveDraft()
    XCTAssertFalse(failed)
    XCTAssertEqual(controller.issue, .save)
    XCTAssertEqual(controller.draft?.text, "new body\n")
    XCTAssertEqual(controller.entries.first?.text, "old body")
    XCTAssertTrue(controller.hasUnsavedEdits)
    XCTAssertFalse(controller.hasPendingWrite)
    let heldFile = heldStorage.appendingPathComponent("quick-copy.json")
    XCTAssertEqual(try Data(contentsOf: heldFile), savedBytes)

    try FileManager.default.removeItem(at: storage)
    try FileManager.default.moveItem(at: heldStorage, to: storage)
    let retried = await controller.saveDraft()
    XCTAssertTrue(retried)
    XCTAssertNil(controller.issue)
    XCTAssertNil(controller.draft)
    XCTAssertEqual(controller.entries.first?.id, id)
    XCTAssertEqual(controller.entries.first?.text, "new body\n")
  }

  func testUnreadableDocumentIsNeverReplacedByAnEmptyList() async throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("quick-copy.json")
    let newer = Data(#"{"schemaVersion":99,"entries":[]}"#.utf8)
    try newer.write(to: fileURL)
    let controller = QuickCopyController(fileURL: fileURL) { _ in false }
    await controller.loadIfNeeded()
    XCTAssertEqual(controller.issue, .load)
    XCTAssertFalse(controller.hasLoaded)
    controller.beginAdding()
    XCTAssertNil(controller.draft)
    let attempted = await controller.saveDraft()
    XCTAssertFalse(attempted)
    XCTAssertEqual(try Data(contentsOf: fileURL), newer)

    try Data(#"{"schemaVersion":1,"entries":[]}"#.utf8).write(to: fileURL)
    await controller.loadIfNeeded()
    XCTAssertTrue(controller.hasLoaded)
    XCTAssertNil(controller.issue)
  }

  func testFailedCopyClearsPreviousSuccessAndCanRetry() async throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    var writes: [String] = []
    var successful = true
    let controller = QuickCopyController(fileURL: directory.appendingPathComponent("entries.json")) {
      writes.append($0)
      return successful
    }
    await controller.loadIfNeeded()
    let first = try await add("First", text: "first", to: controller)
    let second = try await add("Second", text: "second", to: controller)
    XCTAssertFalse(controller.copy(UUID()))
    XCTAssertTrue(controller.copy(first))
    XCTAssertEqual(controller.copiedEntryID, first)

    successful = false
    XCTAssertFalse(controller.copy(second))
    XCTAssertNil(controller.copiedEntryID)
    XCTAssertEqual(controller.issue, .copy(second))

    successful = true
    XCTAssertTrue(controller.copy(second))
    XCTAssertEqual(writes, ["first", "second", "second"])
    XCTAssertNil(controller.issue)
    XCTAssertEqual(controller.copiedEntryID, second)
    controller.clearCopyFeedback()
  }

  func testLatestClickRestartsFeedbackEvenOnTheSameRow() async throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let controller = QuickCopyController(fileURL: directory.appendingPathComponent("entries.json")) {
      _ in true
    }
    await controller.loadIfNeeded()
    let first = try await add("First", text: "one", to: controller)
    let second = try await add("Second", text: "two", to: controller)

    XCTAssertTrue(controller.copy(first))
    try await Task.sleep(for: .milliseconds(800))
    XCTAssertTrue(controller.copy(first))
    try await Task.sleep(for: .milliseconds(800))
    XCTAssertEqual(controller.copiedEntryID, first, "The first tap's expiry cannot clear a retap")

    XCTAssertTrue(controller.copy(second))
    try await Task.sleep(for: .milliseconds(800))
    XCTAssertEqual(controller.copiedEntryID, second, "The previous row cannot clear a new row")
    try await Task.sleep(for: .milliseconds(800))
    XCTAssertNil(controller.copiedEntryID)
  }

  private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseQuickCopyTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func add(_ name: String, text: String, to controller: QuickCopyController) async throws
    -> UUID
  {
    controller.beginAdding()
    let id = try XCTUnwrap(controller.draft?.id)
    controller.setDraftName(name, for: id)
    controller.setDraftText(text, for: id)
    let saved = await controller.saveDraft()
    XCTAssertTrue(saved)
    return id
  }
}
