import AppKit
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class DashboardTaskEditorTests: XCTestCase {
  private func dashboard() throws -> Dashboard {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "sample-apex-dashboard", withExtension: "md"))
    return try ApexDashboardParser().parse(data: Data(contentsOf: url), fileURL: url)
  }

  func testDraftKeepsSelectedColumnInputAndCreationIdentityAcrossNavigation() throws {
    let original = try dashboard()
    let presentation = DashboardTaskPresentation()
    presentation.selectedColumnTitle = "Workstreams"
    presentation.beginAdding(in: original)
    let id = try XCTUnwrap(presentation.draft?.id)
    presentation.draft?.text = "虚构新待办 📝 #sample [[Example]]"
    let request = try XCTUnwrap(presentation.draft?.request)
    XCTAssertEqual(request.id, id)
    XCTAssertEqual(request.destination.columnTitle, "Workstreams")
    XCTAssertEqual(request.destination.cardTitle, "Example project")
    XCTAssertTrue(presentation.isEditing)
    // Navigation may recreate TasksView, but its draft owner survives it.
    XCTAssertEqual(presentation.draft?.text, request.text)
    XCTAssertEqual(presentation.draft?.request?.id, id)
    presentation.finishDraft(id: UUID())
    XCTAssertTrue(presentation.isEditing, "A stale save must not close a later draft")
    presentation.finishDraft(id: id)
    XCTAssertFalse(presentation.isEditing)
    XCTAssertEqual(presentation.selectedColumnTitle, "Workstreams")
  }

  func testSavingInAnotherColumnReturnsToThatColumnAndIgnoresStaleResult() throws {
    let presentation = DashboardTaskPresentation()
    presentation.beginAdding(in: try dashboard())
    presentation.draft?.columnOrder = 1
    presentation.draft?.cardOrder = 0
    presentation.draft?.text = "Chosen column task"
    let request = try XCTUnwrap(presentation.draft?.request)
    presentation.didSave(request)
    XCTAssertEqual(presentation.selectedColumnTitle, "Workstreams")
    XCTAssertNil(presentation.draft)

    presentation.beginAdding(in: try dashboard())
    let laterID = try XCTUnwrap(presentation.draft?.id)
    presentation.didSave(request)
    XCTAssertEqual(presentation.draft?.id, laterID)
  }

  func testEmptyColumnCannotConstructRequestAndFileReselectionDiscardsWrongFileDraft() throws {
    let original = try dashboard()
    let presentation = DashboardTaskPresentation()
    presentation.selectedColumnTitle = "参考"
    presentation.beginAdding(in: original)
    presentation.draft?.text = "A fictional task"
    XCTAssertNil(presentation.draft?.request)
    presentation.reconcileFile(original.fileURL)
    XCTAssertNotNil(presentation.draft)
    presentation.reconcileFile(URL(fileURLWithPath: "/tmp/fictional-other-dashboard.md"))
    XCTAssertNil(presentation.draft)
    XCTAssertNil(presentation.selectedColumnTitle)
  }

  func testInlineDraftTagsAreCaseInsensitiveAndDoNotDuplicateTypedHashtags() throws {
    let original = try dashboard()
    var draft = DashboardTaskDraft(snapshot: original, columnOrder: 0, cardOrder: 0)
    draft.text = "虚构任务 📝 #work"
    XCTAssertTrue(draft.addTag(" #Work "))
    XCTAssertTrue(draft.addTag("work"))
    XCTAssertTrue(draft.addTag("学习/阅读"))
    XCTAssertTrue(draft.addTag("📝"))
    XCTAssertEqual(draft.tags, ["Work", "学习/阅读", "📝"])
    XCTAssertEqual(try XCTUnwrap(draft.request).text, "虚构任务 📝 #work #学习/阅读 #📝")
    draft.newTagText = "bad tag"
    XCTAssertFalse(draft.addTag(draft.newTagText))
    XCTAssertEqual(draft.newTagText, "bad tag", "Invalid input must remain correctable")
    XCTAssertFalse(draft.addTag("1984"))
    XCTAssertFalse(draft.addTag("#"))
    XCTAssertEqual(
      DashboardTaskTags.extract(from: "#Work #work #学习/阅读 [[File#Heading]]"), ["Work", "学习/阅读"])
    draft.text = " \t"
    draft.newTagText = "another"
    XCTAssertNil(draft.request, "Tags cannot turn an empty task field into a writable task")
    XCTAssertEqual(draft.newTagText, "another")
  }

  func testInlineDraftSavesSelectedGroupAndTagsToTemporaryDashboard() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseInlineAdd-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = try dashboard()
    let file = directory.appendingPathComponent("dashboard.md")
    let original = try Data(contentsOf: fixture.fileURL)
    try original.write(to: file)
    let suite = "PulseInlineTags.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let controller = DashboardTaskController(
      configuration: DashboardConfiguration(defaults: defaults))
    await controller.saveDashboard(url: file)
    guard case .loaded(let snapshot) = controller.state else { return XCTFail("Expected fixture") }
    let presentation = DashboardTaskPresentation()
    presentation.selectedColumnTitle = "Workstreams"
    presentation.beginAdding(in: snapshot)
    let creationID = try XCTUnwrap(presentation.draft?.id)
    presentation.draft?.text = "新增虚构任务 📝"
    XCTAssertTrue(presentation.draft?.addTag("sample/read") == true)
    let request = try XCTUnwrap(presentation.draft?.request)
    let operation = try XCTUnwrap(controller.addTask(request: request))
    XCTAssertTrue(controller.isAddingTask)
    let result = await operation.value
    XCTAssertTrue(result)
    presentation.didSave(request)
    XCTAssertNil(presentation.draft)
    XCTAssertEqual(presentation.selectedColumnTitle, "Workstreams")
    await controller.refresh()
    guard case .loaded(let saved) = controller.state else {
      return XCTFail("Expected saved fixture")
    }
    let target = try XCTUnwrap(
      saved.columns.first(where: { $0.title == "Workstreams" })?.cards.first)
    let newTask = try XCTUnwrap(target.tasks.last)
    XCTAssertEqual(newTask.text, "新增虚构任务 📝 #sample/read")
    XCTAssertEqual(newTask.blockIdentifier, "pulse-\(creationID.uuidString.lowercased())")
    XCTAssertFalse(newTask.completed)
    XCTAssertEqual(saved.allTasks.count, snapshot.allTasks.count + 1)
    let reloaded = try String(contentsOf: file, encoding: .utf8)
    XCTAssertEqual(reloaded.components(separatedBy: "#sample/read").count - 1, 1)
    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), original)
  }

  func testSelectionGenerationClearsSameFileDraftButRefreshKeepsIt() throws {
    let original = try dashboard()
    let presentation = DashboardTaskPresentation()
    presentation.reconcileSelection(0)
    presentation.selectedColumnTitle = "Workstreams"
    presentation.beginAdding(in: original)
    presentation.draft?.text = "Unsaved fictional input"
    let id = try XCTUnwrap(presentation.draft?.id)
    // A refresh/navigation event does not constitute a new file selection.
    presentation.reconcileSelection(0)
    presentation.reconcileFile(original.fileURL)
    XCTAssertEqual(presentation.draft?.id, id)
    XCTAssertEqual(presentation.draft?.text, "Unsaved fictional input")
    // Explicitly choosing even the same file invalidates its old snapshot.
    presentation.reconcileSelection(1)
    XCTAssertNil(presentation.draft)
    XCTAssertNil(presentation.selectedColumnTitle)
  }

  func testFailedReselectionDiscardsDraftWithoutMountedTasksView() async throws {
    let suite = "PulseApexDraftReselection.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let original = try dashboard()
    let configuration = DashboardConfiguration(defaults: defaults)
    try configuration.saveDashboard(url: original.fileURL)
    let controller = DashboardTaskController(configuration: configuration)
    await controller.refresh()
    let presentation = DashboardTaskPresentation()
    presentation.reconcileSelection(controller.selectionGeneration)
    presentation.beginAdding(in: original)
    presentation.draft?.text = "Never submit this to the new selection"

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseApexInvalidSelection-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let invalid = directory.appendingPathComponent("invalid.md")
    try Data("Not an Apex Dashboard".utf8).write(to: invalid)
    // No TasksView is constructed: the owner above navigation observes this.
    await controller.saveDashboard(url: invalid)
    presentation.reconcileSelection(controller.selectionGeneration)
    guard case .parseError = controller.state else { return XCTFail("Expected invalid selection") }
    XCTAssertNil(presentation.draft)
    XCTAssertNil(presentation.selectedColumnTitle)
  }

  func testUnreadableReselectionAndRemovalInvalidateDraftButOrdinaryFailureDoesNot() async throws {
    let original = try dashboard()
    for error in [DashboardWriteError.permissionDenied, .fileMissing] {
      let suite = "PulseApexDraftReadFailure.\(UUID())"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let configuration = DashboardConfiguration(defaults: defaults)
      try configuration.saveDashboard(url: original.fileURL)
      let store = DraftReadFailureStore(error: error)
      let controller = DashboardTaskController(configuration: configuration, fileStore: store)
      let presentation = DashboardTaskPresentation()
      presentation.reconcileSelection(controller.selectionGeneration)
      presentation.beginAdding(in: original)
      let initialDraftID = try XCTUnwrap(presentation.draft?.id)
      await controller.refresh()
      presentation.reconcileSelection(controller.selectionGeneration)
      let expected: DashboardConnectionState =
        error == .fileMissing ? .fileMissing : .permissionDenied
      XCTAssertEqual(controller.state, expected)
      XCTAssertEqual(
        presentation.draft?.id, initialDraftID, "A read failure is not a new selection")

      await controller.saveDashboard(url: original.fileURL)
      presentation.reconcileSelection(controller.selectionGeneration)
      XCTAssertEqual(controller.state, expected)
      XCTAssertNil(presentation.draft, "Failed explicit selection must clear the old draft")

      presentation.beginAdding(in: original)
      controller.removeDashboard()
      presentation.reconcileSelection(controller.selectionGeneration)
      XCTAssertNil(presentation.draft)
      XCTAssertNil(presentation.selectedColumnTitle)
      XCTAssertEqual(controller.state, .notConfigured)
    }
  }

  func testApexEditorAndTaskFooterRenderInBothAppearances() async throws {
    let suite = "PulseApexEditor.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let original = try dashboard()
    let configuration = DashboardConfiguration(defaults: defaults)
    try configuration.saveDashboard(url: original.fileURL)
    let controller = DashboardTaskController(configuration: configuration)
    await controller.refresh()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseApexCreationRender")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      for mode in ["list", "editor", "empty-column"] {
        let presentation = DashboardTaskPresentation()
        if mode != "list" {
          if mode == "empty-column" { presentation.selectedColumnTitle = "参考" }
          presentation.beginAdding(in: original)
          presentation.draft?.text = "A fictional task with a long readable title 📝 #sample"
        }
        let host = NSHostingView(
          rootView: TasksView(
            tasks: controller, presentation: presentation, onConfigure: {},
            onOpenTask: { _ in true }
          )
          .frame(width: 360, height: 455)
          .background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 455)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(bitmap.pixelsWide * 455, bitmap.pixelsHigh * 360)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(
          to: directory.appendingPathComponent("\(appearanceName.rawValue)-\(mode).png"))
      }
    }
  }
}

private struct DraftReadFailureStore: DashboardFileStoring {
  let error: DashboardWriteError
  func load(fileURL: URL) async throws -> Dashboard { throw error }

  func setCompleted(_ completed: Bool, task: DashboardTask, snapshot: Dashboard, fileURL: URL)
    async throws -> Dashboard
  {
    throw DashboardWriteError.permissionDenied
  }
}
