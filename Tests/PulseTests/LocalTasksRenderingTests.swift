import AppKit
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class LocalTasksRenderingTests: XCTestCase {
  private func controller() async throws -> LocalTaskController {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseTaskUI-\(UUID())")
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let controller = LocalTaskController(
      store: LocalTaskStore(fileURL: directory.appendingPathComponent("tasks.json")))
    await controller.refresh()
    return controller
  }

  func testDefaultTodoRemainsSelectedAndCanAlwaysFindUntaggedTasks() async throws {
    let controller = try await controller()
    let created = await controller.saveTask(
      id: nil, text: "Visible in Todo", tagIDs: [], newTagNames: [])
    XCTAssertTrue(created)
    let tagID = UUID()
    let addedTag = await controller.createTag(id: tagID, name: "Work")
    XCTAssertTrue(addedTag)
    let presentation = LocalTaskPresentation()
    presentation.reconcileTags(controller.document?.tags ?? [])
    XCTAssertEqual(presentation.selectedFilter, .untagged)
    XCTAssertEqual(
      controller.tasks(matching: presentation.selectedFilter).map(\.text), ["Visible in Todo"])
    presentation.selectedFilter = .tag(tagID)
    let removed = await controller.deleteTag(id: tagID)
    XCTAssertTrue(removed)
    presentation.reconcileTags(controller.document?.tags ?? [])
    XCTAssertEqual(presentation.selectedFilter, .untagged)
  }

  func testIndependentTagIntentPreservesQuickDraftAndCancelWritesNothing() async throws {
    let controller = try await controller()
    let presentation = LocalTaskPresentation()
    presentation.quickDraft.text = "Unsaved input"
    let original = presentation.quickDraft
    presentation.beginCreatingTag()
    presentation.tagIntent?.name = "Empty list"
    XCTAssertEqual(presentation.quickDraft, original)
    XCTAssertNotNil(presentation.tagIntent)
    presentation.tagIntent = nil
    XCTAssertEqual(controller.document, LocalTaskDocument())
    XCTAssertEqual(presentation.quickDraft, original)
    presentation.beginCreatingTag()
    let intent = try XCTUnwrap(presentation.tagIntent)
    let saved = await controller.createTag(id: intent.id, name: "Empty list")
    XCTAssertTrue(saved)
    XCTAssertEqual(controller.document?.tasks, [])
    XCTAssertEqual(controller.document?.tags.map(\.name), ["Empty list"])
  }

  func testDraftsSurviveSwitchingPagesRecreatedViewsAndRepeatedAdd() async throws {
    let controller = try await controller()
    let presentation = LocalTaskPresentation()
    let work = UUID()
    presentation.quickDraft.text = "Todo draft"
    let original = presentation.quickDraft.creationID
    presentation.beginAddingTask()
    XCTAssertEqual(presentation.quickDraft.creationID, original)
    presentation.selectedFilter = .tag(work)
    presentation.quickDraft.text = "Work draft"
    presentation.quickDraft.repeatsDaily = true
    let workDraft = presentation.quickDraft
    _ = LocalTasksView(
      controller: controller, presentation: presentation, onEditingChanged: { _ in })
    _ = LocalTasksView(
      controller: controller, presentation: presentation, onEditingChanged: { _ in })
    presentation.selectedFilter = .untagged
    XCTAssertEqual(presentation.quickDraft.text, "Todo draft")
    XCTAssertEqual(presentation.quickDraft.creationID, original)
    presentation.selectedFilter = .tag(work)
    XCTAssertEqual(presentation.quickDraft, workDraft)
    XCTAssertEqual(presentation.quickDraft.selectedTagID, work)
  }

  func testEditingDoesNotOverwriteRetainedQuickDraft() throws {
    let presentation = LocalTaskPresentation()
    presentation.quickDraft.text = "Unsubmitted quick entry"
    let original = presentation.quickDraft
    let task = LocalTask(text: "Existing")
    presentation.beginEditingTask(task)
    XCTAssertEqual(presentation.editDraft?.taskID, task.id)
    presentation.editDraft?.text = "Edited"
    presentation.finishDraft(id: try XCTUnwrap(presentation.editDraft?.creationID))
    XCTAssertNil(presentation.editDraft)
    XCTAssertEqual(presentation.quickDraft, original)
  }

  func testSelectionIsSingleChoiceIncludingNewTagAndDefault() {
    let work = TaskTag(name: "Work")
    let home = TaskTag(name: "Home")
    var draft = LocalTaskDraft(tagIDs: [work.id])
    draft.newTagText = " Writing "
    draft.acceptPendingTag(availableTags: [work, home])
    XCTAssertEqual(draft.newTagNames, ["Writing"])
    XCTAssertFalse(draft.newTagInputVisible)
    XCTAssertTrue(draft.tagIDs.isEmpty)
    draft.newTagText = " HOME "
    draft.acceptPendingTag(availableTags: [work, home])
    XCTAssertEqual(draft.tagIDs, [home.id])
    XCTAssertTrue(draft.newTagNames.isEmpty)
    draft.newTagText = " todo "
    draft.acceptPendingTag(availableTags: [work, home])
    XCTAssertTrue(draft.tagIDs.isEmpty)
    XCTAssertTrue(draft.newTagNames.isEmpty)
  }

  func testCaptureDeduplicatesAndSuccessClearsOnlyMatchingInputAndCollapses() throws {
    let presentation = LocalTaskPresentation()
    presentation.beginAddingTask()
    presentation.quickDraft.text = "First"
    let submission = try XCTUnwrap(presentation.captureSubmission())
    XCTAssertNil(presentation.captureSubmission())
    let oldFocus = presentation.focusRequest
    let task = LocalTask(id: submission.draft.creationID, text: "First")
    presentation.finishSubmission(submission, saved: true, task: task, tags: [])
    XCTAssertEqual(presentation.quickDraft.text, "")
    XCTAssertNotEqual(presentation.quickDraft.creationID, submission.draft.creationID)
    XCTAssertEqual(presentation.focusRequest, oldFocus)
    XCTAssertFalse(presentation.isComposerExpanded)
    presentation.quickDraft.text = "Second"
    XCTAssertNotNil(presentation.captureSubmission())
  }

  func testPendingSaveDoesNotSwitchTabsOrClearLaterInput() throws {
    let presentation = LocalTaskPresentation()
    let work = TaskTag(name: "Work")
    presentation.quickDraft.text = "Todo pending"
    let submission = try XCTUnwrap(presentation.captureSubmission())
    presentation.selectedFilter = .tag(work.id)
    presentation.quickDraft.text = "Later work input"
    let later = presentation.quickDraft
    presentation.finishSubmission(
      submission, saved: true,
      task: LocalTask(text: "Saved", tagIDs: []), tags: [work])
    XCTAssertEqual(presentation.selectedFilter, .tag(work.id))
    XCTAssertEqual(presentation.quickDraft, later)
    XCTAssertEqual(presentation.quickDrafts[.untagged]?.text, "")
    // A newer edit in the same creation intent must also survive a late reply.
    let second = try XCTUnwrap(presentation.captureSubmission())
    presentation.quickDraft.text = "Changed while saving"
    presentation.finishSubmission(
      second, saved: true,
      task: LocalTask(text: "Saved earlier", tagIDs: [work.id]), tags: [work])
    XCTAssertEqual(presentation.quickDraft.text, "Changed while saving")
  }

  func testSwitchAwayAndBackDuringSaveDoesNotRevealDifferentDestination() throws {
    let presentation = LocalTaskPresentation()
    let work = TaskTag(name: "Work")
    presentation.quickDraft.text = "Move on create"
    presentation.quickDraft.choose(work.id)
    let submission = try XCTUnwrap(presentation.captureSubmission())
    presentation.selectedFilter = .tag(work.id)
    presentation.selectedFilter = .untagged
    presentation.finishSubmission(
      submission, saved: true,
      task: LocalTask(text: "Created", tagIDs: [work.id]), tags: [work])
    XCTAssertEqual(presentation.selectedFilter, .untagged)
  }

  func testFailureRetainsStableCreationIntentAndAllInputForRetry() throws {
    let presentation = LocalTaskPresentation()
    presentation.beginAddingTask()
    presentation.quickDraft.text = "Keep me"
    presentation.quickDraft.newTagText = "Work"
    presentation.quickDraft.acceptPendingTag(availableTags: [])
    presentation.quickDraft.repeatsDaily = true
    let submission = try XCTUnwrap(presentation.captureSubmission())
    presentation.finishSubmission(submission, saved: false, task: nil, tags: [])
    XCTAssertEqual(presentation.quickDraft, submission.draft)
    XCTAssertTrue(presentation.isComposerExpanded)
    let retry = try XCTUnwrap(presentation.captureSubmission())
    XCTAssertEqual(retry.draft.creationID, submission.draft.creationID)
  }

  func testCollapseAndReopenDuringSaveRetainsDraftAndExpandedInput() throws {
    let presentation = LocalTaskPresentation()
    presentation.beginAddingTask()
    presentation.quickDraft.text = "Pending"
    let submission = try XCTUnwrap(presentation.captureSubmission())
    presentation.collapseComposer()
    XCTAssertFalse(presentation.isComposerExpanded)
    XCTAssertEqual(presentation.quickDraft, submission.draft)
    presentation.beginAddingTask()
    presentation.finishSubmission(submission, saved: true, task: nil, tags: [])
    XCTAssertTrue(presentation.isComposerExpanded)
    XCTAssertEqual(presentation.quickDraft.text, "Pending")
    XCTAssertNotEqual(presentation.quickDraft.creationID, submission.draft.creationID)
  }

  func testExpansionIsPerListAndLaterInputIsNotCollapsedByOldSave() throws {
    let presentation = LocalTaskPresentation()
    presentation.beginAddingTask()
    presentation.quickDraft.text = "First"
    let submission = try XCTUnwrap(presentation.captureSubmission())
    let work = UUID()
    presentation.selectedFilter = .tag(work)
    XCTAssertFalse(presentation.isComposerExpanded)
    presentation.beginAddingTask()
    presentation.quickDraft.text = "Work draft"
    presentation.finishSubmission(submission, saved: true, task: nil, tags: [])
    XCTAssertTrue(presentation.isComposerExpanded)
    XCTAssertEqual(presentation.quickDraft.text, "Work draft")
    presentation.selectedFilter = .untagged
    XCTAssertFalse(presentation.isComposerExpanded)
    presentation.beginAddingTask()
    presentation.quickDraft.text = "Next"
    let next = try XCTUnwrap(presentation.captureSubmission())
    presentation.quickDraft.text = "Newer text"
    presentation.finishSubmission(next, saved: true, task: nil, tags: [])
    XCTAssertTrue(presentation.isComposerExpanded)
    XCTAssertEqual(presentation.quickDraft.text, "Newer text")
  }

  func testNativeEscapeCollapsesWithoutDiscardingAndIMEKeepsComposition() {
    let presentation = LocalTaskPresentation()
    presentation.beginAddingTask()
    presentation.quickDraft.text = "中文草稿"
    let field = TaskEntryField(
      text: .constant("中文草稿"), placeholder: "Add", identifier: "escapeTest",
      focusRequest: nil, onSubmit: {}, onFocusChanged: { _ in },
      onCancel: { presentation.collapseComposer() })
    let coordinator = field.makeCoordinator()
    let editor = MarkedTaskTextView()
    editor.marked = true
    XCTAssertFalse(
      coordinator.control(
        NSTextField(), textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
    XCTAssertTrue(presentation.isComposerExpanded)
    editor.marked = false
    XCTAssertTrue(
      coordinator.control(
        NSTextField(), textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
    XCTAssertFalse(presentation.isComposerExpanded)
    XCTAssertEqual(presentation.quickDraft.text, "中文草稿")
  }

  func testHoverSuspendsOnlyForFocusedDirtyOrActiveEditor() {
    let presentation = LocalTaskPresentation()
    XCTAssertFalse(presentation.isEditing)
    presentation.quickDraft.optionsExpanded = true
    XCTAssertFalse(presentation.isEditing)
    presentation.beginAddingTask()
    presentation.composerFocused = true
    XCTAssertTrue(presentation.isEditing)
    presentation.composerFocused = false
    presentation.quickDraft.text = "Draft"
    XCTAssertTrue(presentation.isEditing)
    presentation.collapseComposer()
    XCTAssertFalse(presentation.isEditing)
    XCTAssertEqual(presentation.quickDraft.text, "Draft")
    presentation.beginAddingTask()
    XCTAssertTrue(presentation.isEditing)
    presentation.quickDraft.text = ""
    XCTAssertFalse(presentation.isEditing)
    presentation.beginCreatingTag()
    XCTAssertTrue(presentation.isEditing)
  }

  /// A completed task is a row like any other, so revealing one only has to
  /// select its list and ask for the scroll — there is no section to expand
  /// first.
  func testRevealingCompletedTaskSelectsDestinationAndRequestsScroll() {
    let presentation = LocalTaskPresentation()
    let tag = TaskTag(name: "Work")
    let task = LocalTask(text: "Restored or moved", completed: true, tagIDs: [tag.id])
    presentation.reveal(task, tags: [tag])
    XCTAssertEqual(presentation.selectedFilter, .tag(tag.id))
    XCTAssertEqual(presentation.revealedTaskID, task.id)
  }

  func testTagDragReorderPublishesPreviewAndConvergesOnConfirmedOrder() {
    let presentation = LocalTaskPresentation()
    let work = TaskTag(name: "Work")
    let home = TaskTag(name: "Home")
    let writing = TaskTag(name: "Writing")
    let tags = [work, home, writing]
    presentation.beginTagDrag(writing.id)
    XCTAssertEqual(presentation.draggingTagID, writing.id)
    let toIndex = presentation.commitTagMove(
      writing.id, to: LocalTagDropTarget(pillID: work.id, index: 0, edge: .leading),
      tagIDs: tags.map(\.id))
    XCTAssertEqual(toIndex, 0)
    // The bar shows the drop immediately, before storage has confirmed it.
    XCTAssertEqual(presentation.displayOrder(tags).map(\.id), [writing.id, work.id, home.id])
    XCTAssertNil(presentation.draggingTagID, "the drag is over once it is committed")
    // Storage confirms the same order, so the preview is dropped silently
    // rather than animating a second time.
    presentation.reconcileTagOrder([writing, work, home])
    XCTAssertNil(presentation.pendingTagOrder)
    XCTAssertEqual(
      presentation.displayOrder([writing, work, home]).map(\.id), [writing.id, work.id, home.id])
  }

  func testTagMovesAreIgnoredForTheirOwnSlotUnknownTagsAndBadIndexes() {
    let presentation = LocalTaskPresentation()
    let work = TaskTag(name: "Work")
    let home = TaskTag(name: "Home")
    let tagIDs = [work.id, home.id]
    presentation.beginTagDrag(home.id)
    XCTAssertNil(presentation.commitTagMove(home.id, toIndex: 1, tagIDs: tagIDs))
    XCTAssertNil(presentation.commitTagMove(home.id, toIndex: -3, tagIDs: tagIDs))
    XCTAssertNil(presentation.commitTagMove(home.id, toIndex: 8, tagIDs: tagIDs))
    XCTAssertNil(presentation.commitTagMove(UUID(), toIndex: 0, tagIDs: tagIDs))
    XCTAssertNil(presentation.commitTagMove(home.id, to: nil, tagIDs: tagIDs))
    XCTAssertNil(presentation.pendingTagOrder, "an ignored drop must not move anything")
  }

  func testFailedTagMoveAbandonsThePreview() {
    let presentation = LocalTaskPresentation()
    let work = TaskTag(name: "Work")
    let home = TaskTag(name: "Home")
    presentation.beginTagDrag(home.id)
    XCTAssertEqual(presentation.commitTagMove(home.id, toIndex: 0, tagIDs: [work.id, home.id]), 0)
    XCTAssertEqual(presentation.displayOrder([work, home]).map(\.id), [home.id, work.id])
    presentation.abandonTagMove()
    XCTAssertNil(presentation.pendingTagOrder)
    XCTAssertEqual(presentation.displayOrder([work, home]).map(\.id), [work.id, home.id])
  }

  func testTagPreviewNeverHidesATagCreatedWhileAMoveIsPending() {
    let presentation = LocalTaskPresentation()
    let work = TaskTag(name: "Work")
    let home = TaskTag(name: "Home")
    presentation.beginTagDrag(home.id)
    XCTAssertEqual(presentation.commitTagMove(home.id, toIndex: 0, tagIDs: [work.id, home.id]), 0)
    let writing = TaskTag(name: "Writing")
    XCTAssertEqual(
      presentation.displayOrder([work, home, writing]).map(\.id),
      [home.id, work.id, writing.id])
  }

  func testEngagedTagDropSuspendsPointerDismissalButABareDragDoesNot() {
    let presentation = LocalTaskPresentation()
    XCTAssertFalse(presentation.isInteractionActive)
    presentation.beginTagDrag(UUID())
    XCTAssertFalse(
      presentation.isInteractionActive,
      "a bare drag must not pin the popover open; a cancelled drag can go unnoticed")
    presentation.updateTagDrop(LocalTagDropTarget(pillID: UUID(), index: 0, edge: .leading))
    XCTAssertTrue(presentation.isInteractionActive)
    presentation.updateTagDrop(nil)
    XCTAssertFalse(presentation.isInteractionActive)
  }

  func testReturningFromEditorScrollsNewlyMountedListToSavedTaskOnce() async throws {
    let controller = try await controller()
    for index in 0..<40 {
      let saved = await controller.saveTask(
        id: nil, text: "Task \(index)", tagIDs: [], newTagNames: [])
      XCTAssertTrue(saved)
    }
    let target = try XCTUnwrap(controller.document?.tasks.last)
    let presentation = LocalTaskPresentation()
    presentation.beginEditingTask(target)
    let root = LocalTasksView(
      controller: controller, presentation: presentation, onEditingChanged: { _ in }
    )
    .frame(width: 360, height: 455)
    let host = NSHostingView(rootView: root)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 455),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(30))
    let submission = try XCTUnwrap(presentation.captureEditSubmission())
    presentation.finishEditSubmission(submission, saved: true, task: target, tags: [])
    for _ in 0..<50 {
      host.layoutSubtreeIfNeeded()
      if presentation.revealedTaskID == nil { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertNil(
      presentation.revealedTaskID, "A newly mounted reader must consume the pending reveal")
    func scrollViews(_ view: NSView) -> [NSScrollView] {
      (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews($0) }
    }
    let listScroll = try XCTUnwrap(
      scrollViews(host).first { $0.documentView?.frame.height ?? 0 > 455 })
    XCTAssertGreaterThan(
      listScroll.documentVisibleRect.minY, 100,
      "The actual native scroll position must move beyond the initial viewport to the saved last row"
    )
    // Reconstructing the task surface must not create another reveal request.
    host.rootView = root
    host.layoutSubtreeIfNeeded()
    XCTAssertNil(presentation.revealedTaskID)
  }

  func testTrailingComposerMountsFocusesScrollsAndCollapsesWithoutRestoringOldFieldText()
    async throws
  {
    let controller = try await controller()
    for index in 0..<24 {
      _ = await controller.saveTask(id: nil, text: "Existing \(index)", tagIDs: [], newTagNames: [])
    }
    let presentation = LocalTaskPresentation()
    let root = LocalTasksView(
      controller: controller, presentation: presentation, onEditingChanged: { _ in }
    ).frame(width: 360, height: 455)
    let host = NSHostingView(rootView: root)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 455),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    func fields(_ view: NSView) -> [NSTextField] {
      (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields($0) }
    }
    XCTAssertFalse(fields(host).contains { $0.accessibilityIdentifier() == "localTaskTextField" })
    presentation.beginAddingTask()
    for _ in 0..<30 {
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(10))
    }
    let field = try XCTUnwrap(
      fields(host).first {
        $0.accessibilityIdentifier() == "localTaskTextField"
      })
    let editor = try XCTUnwrap(
      field.currentEditor() as? NSTextView,
      "Explicit expansion must focus the newly mounted field")
    editor.insertText("Fresh task", replacementRange: NSRange(location: 0, length: 0))
    XCTAssertEqual(presentation.quickDraft.text, "Fresh task")
    func scrollViews(_ view: NSView) -> [NSScrollView] {
      (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews($0) }
    }
    let scroll = try XCTUnwrap(scrollViews(host).first { $0.documentView?.frame.height ?? 0 > 455 })
    let fieldInDocument = field.convert(field.bounds, to: scroll.documentView)
    XCTAssertTrue(scroll.documentVisibleRect.intersects(fieldInDocument))
    let snapshot = try XCTUnwrap(presentation.captureSubmission())
    presentation.finishSubmission(snapshot, saved: true, task: nil, tags: [])
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertFalse(presentation.isComposerExpanded)
    XCTAssertEqual(
      presentation.quickDraft.text, "", "Native field teardown cannot restore a saved draft")
    XCTAssertFalse(fields(host).contains { $0.accessibilityIdentifier() == "localTaskTextField" })
  }

  func testAcceptingNewTagRemovesFieldWithoutRestoringAcceptedNameOnEditingEnd() async throws {
    let controller = try await controller()
    let presentation = LocalTaskPresentation()
    presentation.beginEditingTask(LocalTask(text: "Existing task"))
    presentation.editDraft?.newTagInputVisible = true
    let root = LocalTasksView(
      controller: controller, presentation: presentation, onEditingChanged: { _ in }
    ).frame(width: 360, height: 455)
    let host = NSHostingView(rootView: root)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 455),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(30))
    func fields(_ view: NSView) -> [NSTextField] {
      (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields($0) }
    }
    let field = try XCTUnwrap(
      fields(host).first {
        $0.accessibilityIdentifier() == "localTaskNewTagField"
      })
    XCTAssertTrue(window.makeFirstResponder(field))
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    editor.insertText("Writing", replacementRange: NSRange(location: 0, length: 0))
    let delegate = try XCTUnwrap(field.delegate as? TaskEntryField.Coordinator)
    XCTAssertTrue(
      delegate.control(
        field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    // Explicitly deliver AppKit's late end notification before SwiftUI teardown.
    delegate.controlTextDidEndEditing(
      Notification(name: NSControl.textDidEndEditingNotification, object: field))
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertEqual(presentation.editDraft?.newTagNames, ["Writing"])
    XCTAssertEqual(presentation.editDraft?.newTagText, "")
    XCTAssertEqual(presentation.editDraft?.newTagInputVisible, false)
    XCTAssertFalse(fields(host).contains { $0.accessibilityIdentifier() == "localTaskNewTagField" })
  }

  func testNativeEntryInheritsDisabledStateAndUpdatesAccessibleDestination() throws {
    func root(_ placeholder: String, disabled: Bool) -> some View {
      TaskEntryField(
        text: .constant(""), placeholder: placeholder, identifier: "nativeEntry",
        focusRequest: nil, onSubmit: {}, onFocusChanged: { _ in }
      )
      .disabled(disabled).frame(width: 240, height: 30)
    }
    func nativeField(_ view: NSView) -> NSTextField? {
      if let field = view as? NSTextField { return field }
      return view.subviews.lazy.compactMap { nativeField($0) }.first
    }
    let host = NSHostingView(rootView: root("Add to Todo…", disabled: true))
    host.frame = NSRect(x: 0, y: 0, width: 240, height: 30)
    host.layoutSubtreeIfNeeded()
    let field = try XCTUnwrap(nativeField(host))
    XCTAssertFalse(field.isEnabled)
    XCTAssertEqual(field.accessibilityLabel(), "Add to Todo…")
    host.rootView = root("Add to Work…", disabled: false)
    host.layoutSubtreeIfNeeded()
    XCTAssertTrue(field.isEnabled)
    XCTAssertEqual(field.accessibilityLabel(), "Add to Work…")
  }

  func testNewerInputGetsFreshIdentityAfterConsumedCreationAndCanActuallySave() async throws {
    let controller = try await controller()
    let presentation = LocalTaskPresentation()
    presentation.quickDraft.text = "First saved text"
    let submission = try XCTUnwrap(presentation.captureSubmission())
    presentation.quickDraft.text = "Later unsaved input"
    let saved = await controller.saveTask(
      id: nil, text: submission.draft.text,
      tagIDs: [], newTagNames: [], creationID: submission.draft.creationID)
    XCTAssertTrue(saved)
    presentation.finishSubmission(
      submission, saved: true,
      task: controller.document?.tasks.first, tags: [])
    XCTAssertNotEqual(presentation.quickDraft.creationID, submission.draft.creationID)
    let next = try XCTUnwrap(presentation.captureSubmission())
    let nextSaved = await controller.saveTask(
      id: nil, text: next.draft.text,
      tagIDs: [], newTagNames: [], creationID: next.draft.creationID)
    XCTAssertTrue(nextSaved)
    XCTAssertEqual(
      controller.document?.tasks.map(\.text), ["First saved text", "Later unsaved input"])
  }

  func testChangedInputReusesNewlyPersistedTagWithoutDuplicateNameFailure() async throws {
    let controller = try await controller()
    let presentation = LocalTaskPresentation()
    presentation.quickDraft.text = "First saved text"
    presentation.quickDraft.newTagText = "Work"
    presentation.quickDraft.acceptPendingTag(availableTags: [])
    let submission = try XCTUnwrap(presentation.captureSubmission())
    presentation.quickDraft.text = "Later in same list"
    let saved = await controller.saveTask(
      id: nil, text: submission.draft.text,
      tagIDs: [], newTagNames: submission.draft.newTagNames, creationID: submission.draft.creationID
    )
    XCTAssertTrue(saved)
    presentation.finishSubmission(
      submission, saved: true,
      task: controller.document?.tasks.first, tags: controller.document?.tags ?? [])
    let tag = try XCTUnwrap(controller.document?.tags.first)
    XCTAssertEqual(presentation.quickDraft.selectedTagID, tag.id)
    XCTAssertTrue(presentation.quickDraft.newTagNames.isEmpty)
    let next = try XCTUnwrap(presentation.captureSubmission())
    let nextSaved = await controller.saveTask(
      id: nil, text: next.draft.text,
      tagIDs: next.draft.tagIDs, newTagNames: next.draft.newTagNames,
      creationID: next.draft.creationID)
    XCTAssertTrue(nextSaved)
    XCTAssertEqual(controller.document?.tasks.map(\.tagIDs), [[tag.id], [tag.id]])
    XCTAssertEqual(controller.document?.tags.count, 1)
  }

  func testEditorSubmissionDeduplicatesAndDoesNotDiscardNewerEdits() async throws {
    let controller = try await controller()
    let presentation = LocalTaskPresentation()
    let task = LocalTask(text: "Edit me")
    presentation.beginEditingTask(task)
    let snapshot = try XCTUnwrap(presentation.captureEditSubmission())
    _ = LocalTasksView(
      controller: controller, presentation: presentation, onEditingChanged: { _ in })
    XCTAssertNil(presentation.captureEditSubmission(), "Remount cannot queue a second save")
    presentation.editDraft?.text = "Later unsaved edit"
    presentation.finishEditSubmission(snapshot, saved: true, task: task, tags: [])
    XCTAssertEqual(presentation.editDraft?.text, "Later unsaved edit")
    let next = try XCTUnwrap(presentation.captureEditSubmission())
    presentation.finishEditSubmission(next, saved: false, task: nil, tags: [])
    XCTAssertEqual(presentation.editDraft, next, "Failed save retains the retryable draft")
    let retry = try XCTUnwrap(presentation.captureEditSubmission())
    presentation.finishEditSubmission(retry, saved: true, task: task, tags: [])
    XCTAssertNil(presentation.editDraft)
  }

  func testTagSubmissionDeduplicatesRetainsNewerNameAndSelectsOnlyMatchingSuccess() throws {
    let presentation = LocalTaskPresentation()
    presentation.beginCreatingTag()
    presentation.tagIntent?.name = "First tag"
    let snapshot = try XCTUnwrap(presentation.captureTagSubmission())
    XCTAssertNil(presentation.captureTagSubmission())
    presentation.tagIntent?.name = "Later tag"
    presentation.finishTagSubmission(snapshot, saved: true)
    XCTAssertEqual(presentation.tagIntent?.name, "Later tag")
    XCTAssertNotEqual(presentation.tagIntent?.id, snapshot.id)
    XCTAssertEqual(presentation.selectedFilter, .untagged)
    let next = try XCTUnwrap(presentation.captureTagSubmission())
    presentation.finishTagSubmission(next, saved: false)
    XCTAssertEqual(presentation.tagIntent, next)
    let retry = try XCTUnwrap(presentation.captureTagSubmission())
    presentation.finishTagSubmission(retry, saved: true)
    XCTAssertNil(presentation.tagIntent)
    XCTAssertEqual(presentation.selectedFilter, .tag(retry.id))
    XCTAssertTrue(presentation.isComposerExpanded)
  }

  func testNativeQuickEntryEditorUndoRedoRetainsTextEditingSemantics() throws {
    var input = ""
    let root = TaskEntryField(
      text: Binding(get: { input }, set: { input = $0 }),
      placeholder: "Add to Todo…", identifier: "actualQuickEntry", focusRequest: nil,
      onSubmit: {}, onFocusChanged: { _ in }
    ).frame(width: 240, height: 30)
    let host = NSHostingView(rootView: root)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 240, height: 30),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    func nativeField(_ view: NSView) -> NSTextField? {
      if let field = view as? NSTextField { return field }
      return view.subviews.lazy.compactMap { nativeField($0) }.first
    }
    let field = try XCTUnwrap(nativeField(host))
    XCTAssertTrue(window.makeFirstResponder(field))
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    XCTAssertTrue(editor.allowsUndo)
    editor.insertText("Draft text", replacementRange: NSRange(location: 0, length: 0))
    XCTAssertEqual(field.stringValue, "Draft text")
    XCTAssertEqual(input, "Draft text")
    let menu = try XCTUnwrap(PulseApplicationMenu.makeMainMenu().items.first?.submenu)
    let undo = try XCTUnwrap(menu.items.first { $0.title == "Undo" })
    let redo = try XCTUnwrap(menu.items.first { $0.title == "Redo" })
    XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(undo.action), to: window, from: undo))
    XCTAssertEqual(field.stringValue, "")
    XCTAssertEqual(input, "")
    XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(redo.action), to: window, from: redo))
    XCTAssertEqual(field.stringValue, "Draft text")
    XCTAssertEqual(input, "Draft text")
  }

  func testIMEConfirmationDoesNotSubmitAndPlainReturnDoes() {
    var input = "中文"
    var submissions = 0
    var focuses: [Bool] = []
    let field = TaskEntryField(
      text: Binding(get: { input }, set: { input = $0 }),
      placeholder: "Add to Todo…", identifier: "test", focusRequest: nil,
      onSubmit: { submissions += 1 }, onFocusChanged: { focuses.append($0) })
    let delegate = field.makeCoordinator()
    let textView = MarkedTaskTextView()
    let control = NSTextField()
    textView.marked = true
    XCTAssertFalse(
      delegate.control(
        control, textView: textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    XCTAssertEqual(submissions, 0)
    textView.marked = false
    XCTAssertTrue(
      delegate.control(
        control, textView: textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    XCTAssertEqual(submissions, 1)
    XCTAssertFalse(
      delegate.control(
        control, textView: textView, doCommandBy: #selector(NSResponder.insertTab(_:))))
    delegate.controlTextDidBeginEditing(
      Notification(name: NSControl.textDidBeginEditingNotification))
    delegate.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
    XCTAssertEqual(focuses, [true, false])
  }

  func testTaskStatesRenderAtPopoverSizeInBothAppearances() async throws {
    let controller = try await controller()
    let work = TaskTag(name: "Work")
    let createTag = await controller.createTag(id: work.id, name: work.name)
    XCTAssertTrue(createTag)
    for text in [
      "写一份示例 📝 with a long title that wraps across multiple lines", "Completed daily task",
      "To delete",
    ] {
      let saved = await controller.saveTask(
        id: nil, text: text, tagIDs: [work.id], newTagNames: [],
        repeatsDaily: text.contains("daily"))
      XCTAssertTrue(saved)
    }
    let completed = try XCTUnwrap(controller.document?.tasks[1])
    await controller.setCompleted(true, taskID: completed.id)?.value
    let removed = try XCTUnwrap(controller.document?.tasks.last)
    let deleted = await controller.deleteTask(id: removed.id)
    XCTAssertTrue(deleted)
    let empty = try await self.controller()
    let completedOnly = try await self.controller()
    let doneID = UUID()
    _ = await completedOnly.saveTask(
      id: nil, text: "All done", tagIDs: [], newTagNames: [], creationID: doneID)
    await completedOnly.setCompleted(true, taskID: doneID)?.value
    let longList = try await self.controller()
    _ = await longList.createTag(id: work.id, name: work.name)
    for index in 0..<24 {
      _ = await longList.saveTask(
        id: nil, text: "示例事项 \(index + 1)", tagIDs: [work.id], newTagNames: [])
    }
    // Several tags on one bar, so the drag caret has a boundary to sit on.
    let reorderList = try await self.controller()
    let reorderTags = ["Work", "Home", "Writing"].map { TaskTag(name: $0) }
    for tag in reorderTags {
      _ = await reorderList.createTag(id: tag.id, name: tag.name)
    }
    let renderDirectory = URL(fileURLWithPath: "/tmp/PulseMinimalTodoRender", isDirectory: true)
    try FileManager.default.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      for mode in [
        "empty", "list", "completed-only", "options", "editor", "new-tag",
        "rename-tag", "delete-tag", "tag-settings", "composer", "editor-new-tag", "editor-error",
        "long-list", "tag-drag", "tag-reorder",
      ] {
        controller.dismissError()
        let presentation = LocalTaskPresentation()
        let target: LocalTaskController
        switch mode {
        case "empty": target = empty
        case "completed-only": target = completedOnly
        case "long-list": target = longList
        case "tag-drag", "tag-reorder": target = reorderList
        default: target = controller
        }
        presentation.reconcileTags(target.document?.tags ?? [])
        if mode != "empty" { presentation.selectedFilter = .tag(work.id) }
        switch mode {
        case "composer":
          presentation.beginAddingTask()
          presentation.quickDraft.text = "添加一条新的待办"
        case "options":
          presentation.beginAddingTask()
          presentation.quickDraft.newTagInputVisible = true
          presentation.quickDraft.text = "新增虚构待办 👩‍💻"
          presentation.quickDraft.optionsExpanded = true
          presentation.quickDraft.newTagText = "Writing"
        case "editor", "editor-new-tag", "editor-error":
          presentation.beginEditingTask(try XCTUnwrap(controller.document?.tasks.first))
          if mode == "editor-new-tag" {
            presentation.editDraft?.newTagInputVisible = true
            presentation.editDraft?.newTagText = "Personal"
          }
          if mode == "editor-error" {
            _ = await controller.createTag(id: UUID(), name: "Work")
          }
        case "new-tag": presentation.tagIntent = LocalTagIntent(name: "New list")
        case "rename-tag":
          presentation.tagIntent = LocalTagIntent(action: .rename(work.id), name: work.name)
        case "delete-tag":
          presentation.tagIntent = LocalTagIntent(action: .delete(work.id), name: work.name)
        case "completed-only":
          presentation.selectedFilter = .untagged
        case "tag-drag":
          // A live drag of the first tag towards the end of the bar: the
          // dragged pill is dimmed and the caret sits on the last pill's
          // trailing edge, half outside the capsule.
          presentation.selectedFilter = .tag(reorderTags[0].id)
          presentation.beginTagDrag(reorderTags[0].id)
          presentation.updateTagDrop(
            LocalTagDropTarget(pillID: reorderTags[2].id, index: 2, edge: .trailing))
        case "tag-reorder":
          // The optimistic order after that drop, before storage confirms it.
          presentation.selectedFilter = .tag(reorderTags[0].id)
          presentation.pendingTagOrder = [
            reorderTags[1].id, reorderTags[2].id, reorderTags[0].id,
          ]
        default: break
        }
        let content: AnyView
        if mode == "tag-settings" {
          content = AnyView(
            LocalTagSettingsView(controller: controller, onEditingChanged: { _ in }).padding(16))
        } else {
          content = AnyView(
            LocalTasksView(
              controller: target, presentation: presentation,
              onEditingChanged: { _ in }))
        }
        let root = content.frame(width: 360, height: 455).background(
          Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 455)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(bitmap.pixelsWide * 455, bitmap.pixelsHigh * 360)
        for point in [(2, 2), (bitmap.pixelsWide - 2, bitmap.pixelsHigh - 2)] {
          XCTAssertEqual(
            try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1)).alphaComponent, 1, accuracy: 0.01)
        }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
          to: renderDirectory.appendingPathComponent("\(appearanceName.rawValue)-\(mode).png"))
      }
    }
  }

  /// The same states at the height the popover actually leaves for the list once
  /// the toolbar, quota strip and tag bar are in place (380 − 73 − 33). The
  /// 455pt suite above is a stress render; this one is the shipped geometry, so
  /// a footer or composer that outgrows the panel shows up here first.
  func testTaskSurfaceFitsTheRealPopoverRegionInBothAppearances() async throws {
    let controller = try await controller()
    let work = TaskTag(name: "Work")
    let created = await controller.createTag(id: work.id, name: work.name)
    XCTAssertTrue(created)
    for index in 0..<6 {
      _ = await controller.saveTask(
        id: nil,
        text: index == 0
          ? "写一份两行的中文任务，标题足够长，在紧凑的列表里自动折行显示"
          : "示例事项 \(index + 1)",
        tagIDs: [work.id], newTagNames: [])
    }
    let empty = try await self.controller()
    let longList = try await self.controller()
    for index in 0..<24 {
      _ = await longList.saveTask(
        id: nil, text: "示例事项 \(index + 1)", tagIDs: [], newTagNames: [])
    }
    let regionHeight: CGFloat = 274
    let directory = URL(fileURLWithPath: "/tmp/PulseMinimalTodoRender", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      for mode in ["list", "empty", "long-list", "composer"] {
        let presentation = LocalTaskPresentation()
        let target: LocalTaskController
        if mode == "empty" {
          target = empty
        } else if mode == "long-list" {
          target = longList
        } else {
          target = controller
        }
        presentation.reconcileTags(target.document?.tags ?? [])
        if mode == "composer" {
          presentation.beginAddingTask()
          presentation.quickDraft.text = "在真实高度下展开输入"
        }
        let host = NSHostingView(
          rootView: LocalTasksView(
            controller: target, presentation: presentation, onEditingChanged: { _ in })
            .frame(width: 360, height: regionHeight)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: regionHeight)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(
          Double(bitmap.pixelsWide) * regionHeight,
          Double(bitmap.pixelsHigh) * 360, accuracy: 1)
        for point in [(2, 2), (bitmap.pixelsWide - 2, bitmap.pixelsHigh - 2)] {
          XCTAssertEqual(
            try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1)).alphaComponent, 1,
            accuracy: 0.01)
        }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
          to: directory.appendingPathComponent(
            "\(appearanceName.rawValue)-region-\(mode).png"))
      }
    }
  }

  /// A task that is still saving keeps the exact geometry it had at rest. The
  /// pending spinner used to *replace* the check control, so the row changed
  /// shape mid-save and the completion animation that follows ran against a
  /// view that had just been rebuilt.
  func testPendingCompletionDoesNotChangeRowGeometry() throws {
    let task = LocalTask(text: "Geometry must not shift while saving")
    let idle = try rowFrame(task: task, isPending: false)
    let saving = try rowFrame(task: task, isPending: true)
    XCTAssertGreaterThan(idle.height, 30)
    XCTAssertEqual(idle.width, saving.width, accuracy: 0.5, "Row width is unchanged")
    XCTAssertEqual(idle.height, saving.height, accuracy: 0.5, "Row height is unchanged")
  }

  /// The tag bar's selection plate has to be visible in an off-window render:
  /// a matched-geometry plate that silently fails to draw would leave the
  /// selected tab looking unselected in every snapshot.
  func testSelectedTagPlateRendersInBothAppearances() throws {
    let directory = URL(fileURLWithPath: "/tmp/PulseMinimalTodoRender", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      let host = NSHostingView(
        rootView: TagPlatePreview().frame(width: 360, height: 76, alignment: .topLeading)
          .background(Color(nsColor: .windowBackgroundColor)))
      host.appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
      host.frame = NSRect(x: 0, y: 0, width: 360, height: 76)
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)

      // Sample inside each capsule but before its label: the capsule's left cap
      // is a semicircle of radius 13, so x = start+2…start+8 is inside the fill
      // and clear of any glyph (the label begins after 9pt of padding). Both
      // candidate vertical mappings are averaged, so the check does not depend
      // on which way the cached bitmap's rows run.
      let selectedWidth =
        ("Todo" as NSString).size(withAttributes: [
          .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ]).width + 18
      let idleWidth =
        ("Project" as NSString).size(withAttributes: [
          .font: NSFont.systemFont(ofSize: 13, weight: .regular)
        ]).width + 18
      XCTAssertGreaterThan(idleWidth, 0)
      let idleStart = 20 + Int(selectedWidth.rounded()) + 4
      // Sampling works in points and converts through the bitmap's real scale,
      // because a Retina cache doubles the pixel grid the assertion reads.
      let scale = CGFloat(bitmap.pixelsWide) / 360
      // The pill occupies top-relative y 20…46; that band and its mirror are
      // both sampled, so the answer does not depend on the bitmap's row order.
      let bands = [20..<46, 30..<56]
      let selectedBands = bands.map {
        averageColor(in: bitmap, xStart: 20, yBand: $0, scale: scale)
      }
      let idleBands = bands.map {
        averageColor(in: bitmap, xStart: idleStart, yBand: $0, scale: scale)
      }
      // The mirrored band is mostly background by construction, so take the
      // strongest disagreement between matching bands instead of averaging.
      let distance = zip(selectedBands, idleBands)
        .map { pair in zip(pair.0, pair.1).map { abs($0 - $1) }.max() ?? 0 }
        .max() ?? 0
      let selectedDescription = selectedBands
        .map { $0.map { String(format: "%.3f", $0) }.joined(separator: ",") }
        .joined(separator: " | ")
      let idleDescription = idleBands
        .map { $0.map { String(format: "%.3f", $0) }.joined(separator: ",") }
        .joined(separator: " | ")
      XCTAssertGreaterThan(
        distance, 0.01,
        "The selected pill must be filled (\(appearanceName.rawValue)): selected ("
          + selectedDescription + ") idle (" + idleDescription + ")")
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
        to: directory.appendingPathComponent("\(appearanceName.rawValue)-tag-plate.png"))
    }
  }

  // MARK: - Helpers

  /// Mean RGB over the left-cap columns of one pill band, converted from points
  /// through the bitmap's actual pixel scale. The label begins after 9pt of
  /// padding, so x = start+2…start+8 samples only fill (or bare background).
  /// Returns `[red, green, blue]`.
  private func averageColor(
    in bitmap: NSBitmapImageRep, xStart: Int, yBand: Range<Int>, scale: CGFloat
  ) -> [CGFloat] {
    var sum: [CGFloat] = [0, 0, 0]
    var count = 0
    for x in Int((CGFloat(xStart) + 2) * scale)..<Int((CGFloat(xStart) + 9) * scale) {
      for y in Int(CGFloat(yBand.lowerBound) * scale)..<Int(CGFloat(yBand.upperBound) * scale) {
        guard let color = bitmap.colorAt(x: x, y: y) else { continue }
        sum[0] += color.redComponent
        sum[1] += color.greenComponent
        sum[2] += color.blueComponent
        count += 1
      }
    }
    guard count > 0 else { return [1, 1, 1] }
    return sum.map { $0 / CGFloat(count) }
  }

  private func rowFrame(task: LocalTask, isPending: Bool) throws -> CGRect {
    let capture = FrameCapture()
    let row = LocalTaskRow(
      task: task, isPending: isPending, onToggle: {}, onEdit: {}, onDelete: {})
      .background(
        GeometryReader { proxy in
          Color.clear.preference(key: RowFrameKey.self, value: proxy.frame(in: .local))
        })
      .overlayPreferenceValue(RowFrameKey.self) { frame in
        GeometryReader { _ in
          FrameCaptureView(frame: frame, capture: capture)
        }
        .allowsHitTesting(false)
      }
      .frame(width: 332)
    let host = NSHostingView(rootView: row)
    host.frame = NSRect(x: 0, y: 0, width: 332, height: 120)
    host.layoutSubtreeIfNeeded()
    return try XCTUnwrap(capture.frame, "Row frame was never measured")
  }
}

/// Renders one selected and one idle pill side by side in the same namespace,
/// exactly as the tag bar does.
private struct TagPlatePreview: View {
  @Namespace private var plate

  var body: some View {
    HStack(spacing: 4) {
      PulsePillTab(title: "Todo", isSelected: true, action: {}, plateNamespace: plate)
      PulsePillTab(title: "Project", isSelected: false, action: {}, plateNamespace: plate)
    }
    .padding(20)
  }
}

private struct RowFrameKey: PreferenceKey {
  static let defaultValue: CGRect = .null
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    let next = nextValue()
    if next != .null { value = next }
  }
}

@MainActor
private final class FrameCapture {
  var frame: CGRect?
}

private struct FrameCaptureView: NSViewRepresentable {
  let frame: CGRect
  let capture: FrameCapture
  func makeNSView(context: Context) -> NSView {
    capture.frame = frame
    return NSView()
  }
  func updateNSView(_ nsView: NSView, context: Context) { capture.frame = frame }
}

@MainActor
private final class MarkedTaskTextView: NSTextView {
  var marked = false
  override func hasMarkedText() -> Bool { marked }
}
