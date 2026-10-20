import AppKit
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class LocalTasksRenderingTests: XCTestCase {
  func testLocalTasksAndEditorRenderAtPopoverSizeInBothAppearances() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseLocalRender-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let controller = LocalTaskController(
      store: LocalTaskStore(fileURL: directory.appendingPathComponent("tasks.json")))
    await controller.refresh()
    let added = await controller.saveTask(
      id: nil,
      text:
        "写一份虚构示例 📝 with a long title that wraps across multiple lines in a compact menu bar task list",
      tagIDs: [], newTagNames: ["Work", "写作"])
    XCTAssertTrue(added)
    let first = try XCTUnwrap(controller.document?.tasks.first)
    await controller.setCompleted(true, taskID: first.id)?.value
    let secondAdded = await controller.saveTask(
      id: nil, text: "Another fictional task", tagIDs: [], newTagNames: [])
    XCTAssertTrue(secondAdded)

    let renderDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseBuiltinTaskRender")
    try FileManager.default.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
      for mode in ["list-incomplete", "editor", "inline-add"] {
        let presentation = LocalTaskPresentation()
        if mode == "editor" {
          presentation.beginEditingTask(first)
          presentation.draft?.newTagNames = ["Draft tag"]
        } else if mode == "inline-add" {
          presentation.beginAddingTask()
          presentation.draft?.text = "新增虚构待办 👩‍💻 with text that wraps inside the compact footer"
          presentation.draft?.tagIDs = Set(controller.document?.tags.map(\.id) ?? [])
          presentation.draft?.newTagNames = [
            "A deliberately long fictional tag label kept inside the native menu"
          ]
          presentation.draft?.newTagText = "Another tag"
          // The default tab is the first tag, so only its task is listed.
          XCTAssertEqual(controller.tasks(matching: presentation.selectedFilter).count, 1)
          XCTAssertNil(presentation.draft?.taskID)
        }
        // The actual task surface receives both completed and incomplete rows.
        // Home hides the completed one; storage still retains it for reload.
        XCTAssertEqual(controller.document?.tasks.filter(\.completed).count, 1)
        let rootView = LocalTasksView(
          controller: controller, presentation: presentation, onEditingChanged: { _ in }
        )
        .frame(width: 360, height: 455)
        .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: rootView)
        host.appearance = appearance
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 455)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(bitmap.pixelsWide * 455, bitmap.pixelsHigh * 360)
        for point in [(2, 2), (bitmap.pixelsWide - 2, bitmap.pixelsHigh - 2)] {
          let color = try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1))
          XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01)
        }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(
          to: renderDirectory.appendingPathComponent(
            "\(appearanceName.rawValue)-\(mode).png"))
      }
    }
  }

  func testReturningToDraftReconcilesDeletedTagsWithoutLosingInput() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseDraftTags-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let controller = LocalTaskController(
      store: LocalTaskStore(fileURL: directory.appendingPathComponent("tasks.json")))
    await controller.refresh()
    let added = await controller.saveTask(
      id: nil, text: "Original", tagIDs: [], newTagNames: ["Work"])
    XCTAssertTrue(added)
    let task = try XCTUnwrap(controller.document?.tasks.first)
    let tag = try XCTUnwrap(controller.document?.tags.first)
    let presentation = LocalTaskPresentation()
    presentation.selectedFilter = .tag(tag.id)
    presentation.beginEditingTask(task)
    presentation.draft?.text = "Unsaved edited text"
    presentation.draft?.newTagNames = ["New tag"]
    let deleted = await controller.deleteTag(id: tag.id)
    XCTAssertTrue(deleted)
    presentation.reconcileTags(controller.document?.tags ?? [])
    // With no tags left, the bar falls back to its guidance tab.
    XCTAssertEqual(presentation.selectedFilter, .untagged)
    let draft = try XCTUnwrap(presentation.draft)
    XCTAssertEqual(draft.text, "Unsaved edited text")
    XCTAssertTrue(draft.tagIDs.isEmpty)
    let saved = await controller.saveTask(
      id: draft.taskID, text: draft.text, tagIDs: draft.tagIDs, newTagNames: draft.newTagNames,
      creationID: draft.creationID)
    XCTAssertTrue(saved)
    XCTAssertEqual(controller.document?.tasks.first?.text, "Unsaved edited text")
  }

  func testDraftRetainsInputAcrossRecreatedViewsAndDefaultsToSelectedTag() {
    let presentation = LocalTaskPresentation()
    let tagID = UUID()
    presentation.selectedFilter = .tag(tagID)
    presentation.beginAddingTask()
    presentation.draft?.text = "Unsaved input"
    presentation.draft?.newTagNames = ["Draft tag"]
    XCTAssertTrue(presentation.isEditing)
    XCTAssertEqual(presentation.draft?.tagIDs, [tagID])
    // Pages may reconstruct the view; the draft owner outlives those pages.
    let controller = LocalTaskController(
      store: LocalTaskStore(
        fileURL:
          FileManager.default.temporaryDirectory.appendingPathComponent(
            "UnusedRender-\(UUID()).json")))
    _ = LocalTasksView(
      controller: controller, presentation: presentation, onEditingChanged: { _ in })
    _ = LocalTasksView(
      controller: controller, presentation: presentation, onEditingChanged: { _ in })
    XCTAssertEqual(presentation.draft?.text, "Unsaved input")
    XCTAssertEqual(presentation.draft?.newTagNames, ["Draft tag"])
  }

  func testInlineCreationSavesExistingTagsAndPendingNewTagWithoutDuplicates() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseInlineTags-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("tasks.json")
    let controller = LocalTaskController(store: LocalTaskStore(fileURL: fileURL))
    await controller.refresh()
    let seeded = await controller.saveTask(
      id: nil, text: "Existing fictional task", tagIDs: [], newTagNames: ["Work", "Reference"])
    XCTAssertTrue(seeded)
    let work = try XCTUnwrap(controller.document?.tags.first(where: { $0.name == "Work" }))
    let reference = try XCTUnwrap(
      controller.document?.tags.first(where: { $0.name == "Reference" }))
    let presentation = LocalTaskPresentation()
    presentation.selectedFilter = .tag(work.id)
    presentation.beginAddingTask()
    var draft = try XCTUnwrap(presentation.draft)
    let id = draft.creationID
    XCTAssertEqual(draft.tagIDs, [work.id])
    draft.text = "Inline fictional task 📝"
    draft.newTagText = " Writing "
    draft.acceptPendingTag(availableTags: controller.document?.tags ?? [])
    draft.newTagText = "writing"
    draft.acceptPendingTag(availableTags: controller.document?.tags ?? [])
    XCTAssertEqual(draft.newTagNames, ["Writing"])
    XCTAssertTrue(draft.newTagText.isEmpty, "A duplicate staged tag must not block task Save")
    draft.newTagText = "reference"
    draft.acceptPendingTag(availableTags: controller.document?.tags ?? [])
    XCTAssertEqual(draft.tagIDs, [work.id, reference.id])
    // Direct task Save must consume the remaining new-tag field just like Add.
    draft.newTagText = "Notes"
    draft.acceptPendingTag(availableTags: controller.document?.tags ?? [])
    presentation.draft = draft
    let saved = await controller.saveTask(
      id: nil, text: draft.text, tagIDs: draft.tagIDs, newTagNames: draft.newTagNames,
      creationID: draft.creationID)
    XCTAssertTrue(saved)
    let task = try XCTUnwrap(controller.document?.tasks.first(where: { $0.id == id }))
    presentation.didCreate(id: id, task: task)
    XCTAssertNil(presentation.draft)
    XCTAssertEqual(presentation.selectedFilter, .tag(work.id))
    XCTAssertEqual(controller.tasks(matching: .tag(work.id)).count, 2)
    XCTAssertEqual(task.tagIDs.count, 4)
    XCTAssertEqual(
      Set(controller.document?.tags.map(\.name) ?? []), ["Work", "Reference", "Writing", "Notes"])
    let restored = LocalTaskController(store: LocalTaskStore(fileURL: fileURL))
    await restored.refresh()
    XCTAssertEqual(restored.document?.tasks.first(where: { $0.id == id }), task)
  }

  func testConfirmedCreationRetainsMatchingFilterAndRevealsOtherwiseHiddenTask() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseInlineFilter-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let controller = LocalTaskController(
      store: LocalTaskStore(fileURL: directory.appendingPathComponent("tasks.json")))
    await controller.refresh()
    let seeded = await controller.saveTask(
      id: nil, text: "Seed", tagIDs: [], newTagNames: ["Work"])
    XCTAssertTrue(seeded)
    let work = try XCTUnwrap(controller.document?.tags.first)
    let presentation = LocalTaskPresentation()
    for filter in [LocalTaskFilter.tag(work.id), .untagged] {
      // Mirrors what LocalTasksView does when the surface appears.
      presentation.reconcileTags(controller.document?.tags ?? [])
      presentation.selectedFilter = filter
      presentation.beginAddingTask()
      var draft = try XCTUnwrap(presentation.draft)
      draft.text = "Task outside current category"
      if case .tag = filter {
        draft.tagIDs = []
      } else {
        draft.newTagText = "Work"
        draft.acceptPendingTag(availableTags: controller.document?.tags ?? [])
      }
      presentation.draft = draft
      let saved = await controller.saveTask(
        id: nil, text: draft.text, tagIDs: draft.tagIDs, newTagNames: draft.newTagNames,
        creationID: draft.creationID)
      XCTAssertTrue(saved)
      let actual = try XCTUnwrap(
        controller.document?.tasks.first(where: { $0.id == draft.creationID }))
      presentation.didCreate(id: draft.creationID, task: actual)
      // Tags are the only tabs, so a task created outside the shown tag reveals
      // that task's own tag instead of returning to an "All" list.
      if case .tag = filter {
        XCTAssertEqual(presentation.selectedFilter, .untagged)
      } else {
        XCTAssertEqual(presentation.selectedFilter, .tag(work.id))
      }
      XCTAssertTrue(
        controller.tasks(matching: presentation.selectedFilter).contains(where: {
          $0.id == actual.id
        }))
    }
  }

  func testStaleSaveCannotClearLaterDraftOrChangeItsFilter() throws {
    let presentation = LocalTaskPresentation()
    presentation.beginAddingTask()
    let earlier = try XCTUnwrap(presentation.draft)
    presentation.selectedFilter = .untagged
    presentation.beginAddingTask()
    presentation.draft?.text = "Later unsaved input"
    let later = try XCTUnwrap(presentation.draft)
    presentation.didCreate(
      id: earlier.creationID,
      task: LocalTask(id: earlier.creationID, text: "Earlier", tagIDs: [UUID()]))
    XCTAssertEqual(presentation.draft?.creationID, later.creationID)
    XCTAssertEqual(presentation.draft?.text, "Later unsaved input")
    XCTAssertEqual(presentation.selectedFilter, .untagged)
    presentation.finishDraft(id: earlier.creationID)
    XCTAssertNotNil(presentation.draft)
  }

  func testFailedInlineSaveRetainsDraftTextTagsAndStableCreationID() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseInlineFailure-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("tasks.json")
    let controller = LocalTaskController(
      store: LocalTaskStore(fileURL: fileURL, writer: FailingInlineLocalWriter()))
    await controller.refresh()
    let presentation = LocalTaskPresentation()
    presentation.beginAddingTask()
    presentation.draft?.text = "Retain this fictional input"
    presentation.draft?.newTagText = "Work"
    var draft = try XCTUnwrap(presentation.draft)
    draft.acceptPendingTag(availableTags: controller.document?.tags ?? [])
    presentation.draft = draft
    let saved = await controller.saveTask(
      id: nil, text: draft.text, tagIDs: draft.tagIDs, newTagNames: draft.newTagNames,
      creationID: draft.creationID)
    if saved {
      presentation.didCreate(id: draft.creationID, task: controller.document?.tasks.first)
    }
    XCTAssertFalse(saved)
    XCTAssertNotNil(controller.errorMessage)
    XCTAssertEqual(presentation.draft?.creationID, draft.creationID)
    XCTAssertEqual(presentation.draft?.text, "Retain this fictional input")
    XCTAssertEqual(presentation.draft?.newTagNames, ["Work"])
    XCTAssertEqual(controller.document?.tasks.count, 0)
    let retry = LocalTaskController(store: LocalTaskStore(fileURL: fileURL))
    await retry.refresh()
    let retried = await retry.saveTask(
      id: nil, text: draft.text, tagIDs: draft.tagIDs, newTagNames: draft.newTagNames,
      creationID: draft.creationID)
    XCTAssertTrue(retried)
    let task = try XCTUnwrap(retry.document?.tasks.first)
    presentation.didCreate(id: draft.creationID, task: task)
    XCTAssertNil(presentation.draft)
    XCTAssertEqual(task.id, draft.creationID)
  }

  func testExistingRowCannotReplaceUnsavedCreationButCheckboxAndFiltersRemainAvailable()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseInlineRowGuard-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let controller = LocalTaskController(
      store: LocalTaskStore(fileURL: directory.appendingPathComponent("tasks.json")))
    await controller.refresh()
    let seeded = await controller.saveTask(
      id: nil, text: "Existing task", tagIDs: [], newTagNames: [])
    XCTAssertTrue(seeded)
    let task = try XCTUnwrap(controller.document?.tasks.first)
    let presentation = LocalTaskPresentation()
    presentation.beginAddingTask()
    presentation.draft?.text = "Unsaved new task"
    let id = try XCTUnwrap(presentation.draft?.creationID)
    presentation.beginEditingTask(task)
    XCTAssertEqual(presentation.draft?.creationID, id)
    XCTAssertEqual(presentation.draft?.text, "Unsaved new task")
    XCTAssertNil(presentation.draft?.taskID)
    await controller.setCompleted(true, taskID: task.id)?.value
    XCTAssertTrue(controller.document?.tasks.first?.completed == true)
    presentation.selectedFilter = .untagged
    XCTAssertEqual(presentation.draft?.creationID, id)
    XCTAssertEqual(controller.tasks(matching: .untagged).count, 1)
    presentation.finishDraft(id: id)
    presentation.beginEditingTask(task)
    XCTAssertEqual(presentation.draft?.taskID, task.id)
  }

  /// Evidence render for the redesigned surface: tag-only tabs with a filled
  /// selection, open rows before completed ones, the daily-repeat marker, and
  /// an empty vocabulary that still offers its guidance tab.
  func testTagOnlySurfaceRendersCompletedRepeatingAndEmptyStatesInBothAppearances()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseTagSurface-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let controller = LocalTaskController(
      store: LocalTaskStore(fileURL: directory.appendingPathComponent("tasks.json")))
    await controller.refresh()
    let work = try XCTUnwrap(TaskTag(name: "Work"))
    let created = await controller.saveTask(
      id: nil, text: "Open task", tagIDs: [], newTagNames: [work.name])
    XCTAssertTrue(created)
    let repeatable = try XCTUnwrap(controller.document?.tasks.first)
    let saved = await controller.saveTask(
      id: repeatable.id, text: "Daily stand-up", tagIDs: repeatable.tagIDs, newTagNames: [],
      repeatsDaily: true)
    XCTAssertTrue(saved)
    let done = await controller.saveTask(
      id: nil, text: "Shipped earlier", tagIDs: repeatable.tagIDs, newTagNames: [])
    XCTAssertTrue(done)
    let completed = try XCTUnwrap(
      controller.document?.tasks.first(where: { $0.text == "Shipped earlier" }))
    await controller.setCompleted(true, taskID: completed.id)?.value
    XCTAssertTrue(
      try XCTUnwrap(controller.document?.tasks.first(where: { $0.id == completed.id })).completed)
    let repeated = try XCTUnwrap(
      controller.document?.tasks.first(where: { $0.id == repeatable.id }))
    XCTAssertFalse(repeated.completed, "A daily task opens unfinished")

    let renderDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseTaskSurfaceRender")
    try FileManager.default.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
    let empty = LocalTaskController(
      store: LocalTaskStore(
        fileURL: directory.appendingPathComponent("empty-\(UUID()).json")))
    await empty.refresh()
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
      let cases: [(String, LocalTaskController, LocalTaskPresentation)] = [
        ("list", controller, { let p = LocalTaskPresentation()
          p.selectedFilter = .tag(repeated.tagIDs.first ?? UUID())
          return p }()),
        ("empty", empty, LocalTaskPresentation()),
      ]
      for (name, target, presentation) in cases {
        let host = NSHostingView(
          rootView:
            LocalTasksView(
              controller: target, presentation: presentation, onEditingChanged: { _ in })
            .frame(width: 360, height: 455)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = appearance
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 455)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(bitmap.pixelsWide * 455, bitmap.pixelsHigh * 360)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(
          to: renderDirectory.appendingPathComponent(
            "\(appearanceName.rawValue)-\(name).png"))
      }
    }

    // The surface keeps completed rows visible, dimmed, after the open ones.
    XCTAssertEqual(
      controller.incompleteTasks(matching: .tag(repeated.tagIDs.first ?? UUID())).map(\.text),
      ["Daily stand-up"])
    XCTAssertEqual(
      controller.completedTasks(matching: .tag(repeated.tagIDs.first ?? UUID())).map(\.text),
      ["Shipped earlier"])
    // An empty tag vocabulary falls back to the single guidance tab, not "All".
    XCTAssertEqual(empty.document?.tags.isEmpty, true)
    let guidance = LocalTaskPresentation()
    XCTAssertEqual(guidance.selectedFilter, .untagged)
    guidance.reconcileTags(empty.document?.tags ?? [])
    XCTAssertEqual(guidance.selectedFilter, .untagged)
  }

  /// A task created from "New tag…" must not inherit the shown tag.
  func testNewTagIntentStagesNoExistingTag() throws {
    let tag = TaskTag(name: "Work")
    let presentation = LocalTaskPresentation()
    presentation.reconcileTags([tag])
    XCTAssertEqual(presentation.selectedFilter, .tag(tag.id))
    presentation.beginAddingTaskWithNewTag()
    XCTAssertEqual(presentation.selectedFilter, .untagged)
    XCTAssertEqual(presentation.draft?.tagIDs, [])
    XCTAssertNil(presentation.draft?.taskID)
  }
  /// A multi-tag task must reveal the same tab on every launch: `Set` iteration
  /// order is not a stable tie-breaker for selection.
  func testRevealedTagIsOldestCreationRatherThanSetOrder() throws {
    let first = TaskTag(name: "Work")
    let second = TaskTag(name: "Home")
    for _ in 0..<20 {
      let presentation = LocalTaskPresentation()
      presentation.reconcileTags([first, second])
      let draft = LocalTaskDraft()
      presentation.draft = draft
      presentation.didCreate(
        id: draft.creationID,
        task: LocalTask(id: draft.creationID, text: "Multi", tagIDs: [first.id, second.id]))
      XCTAssertEqual(presentation.selectedFilter, .tag(first.id))
      XCTAssertNil(presentation.draft)
    }
  }

}

private struct FailingInlineLocalWriter: LocalTaskFileWriting {
  func write(_ data: Data, to fileURL: URL) throws { throw LocalTaskStoreError.saveFailed }
}
