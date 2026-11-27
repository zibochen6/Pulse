import AppKit
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class TodayTaskBridgeTests: XCTestCase {
  func testPairingCanonicalizesTheVaultAndPausesOnlyThePreviousChannel() async throws {
    let fixture = try fixture()
    let vault = try fixture.makeVault("first/Personal")
    let alias = fixture.directory.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: vault)
    let storage = fixture.storage()
    let paired = try await storage.connect(to: vault, replacing: nil)
    let viaAlias = try await storage.connect(to: alias, replacing: paired)
    XCTAssertEqual(viaAlias, paired)
    let original = try await storage.enqueue(.init(kind: .add, title: "First"), for: paired)
    XCTAssertEqual(original.tasks.map(\.title), ["First"])

    let other = try await storage.connect(
      to: fixture.makeVault("second/Personal"), replacing: paired)
    XCTAssertNotEqual(other.id, paired.id)
    XCTAssertFalse(try fixture.client(paired).enabled)
    XCTAssertTrue(try fixture.client(other).enabled)
    XCTAssertEqual(try fixture.client(other).operations.count, 0)

    _ = try await storage.connect(to: vault, replacing: other)
    XCTAssertFalse(try fixture.client(other).enabled)
    XCTAssertEqual(try fixture.client(paired).operations.map(\.title), ["First"])
    let mode =
      try FileManager.default.attributesOfItem(atPath: fixture.channel(paired).path)[
        .posixPermissions] as? Int
    XCTAssertEqual(mode, 0o700)
  }

  func testOfflineQueueSurvivesRestartAndClearsOnlyAfterAValidSnapshotAndReceipt() async throws {
    let fixture = try fixture()
    let storage = fixture.storage()
    let vault = try await storage.connect(to: fixture.makeVault("Personal"), replacing: nil)
    try fixture.publish(vault, tasks: [fixture.quick, fixture.project])
    let initial = try await storage.refresh(vault)
    XCTAssertEqual(initial.connection, .connected)
    XCTAssertEqual(initial.tasks.map(\.id), [fixture.quick.id, fixture.project.id])
    try FileManager.default.removeItem(
      at: fixture.channel(vault).appendingPathComponent("board.json"))

    let reopened = fixture.storage()
    let offline = try await reopened.refresh(vault)
    XCTAssertEqual(offline.connection, .waiting)
    XCTAssertEqual(offline.tasks.count, 2)
    let finish = TodayBridgeOperation.targeting(
      offline.tasks[0], day: fixture.day, kind: .complete, completed: true)
    let remove = TodayBridgeOperation.targeting(offline.tasks[1], day: fixture.day, kind: .delete)
    let first = TodayBridgeOperation(kind: .add, title: "同名任务")
    let second = TodayBridgeOperation(kind: .add, title: "同名任务")
    for operation in [finish, remove, first, second] {
      _ = try await reopened.enqueue(operation, for: vault)
    }
    let queued = try await fixture.storage().refresh(vault)
    XCTAssertEqual(queued.operations.map(\.id), [finish.id, remove.id, first.id, second.id])
    XCTAssertEqual(
      queued.tasks.map(\.id), [fixture.quick.id, fixture.project.id, first.id, second.id])
    XCTAssertEqual(queued.tasks.map(\.pendingOperation), [.complete, .delete, .add, .add])
    XCTAssertTrue(try XCTUnwrap(queued.tasks.first).completed)
    let waiting = TaskListSections(queued.tasks, completed: \.completed, pending: \.isPending)
    XCTAssertEqual(waiting.confirmedCount, 0)
    XCTAssertEqual(waiting.rows(expanded: false).map(\.id), queued.tasks.map { .task($0.id) })

    let receipts = [finish, remove, first, second].map {
      TodayBridgeReceipt(id: $0.id, code: .applied)
    }
    try fixture.publish(
      vault, tasks: [fixture.quick, fixture.project], issue: .sourceUnavailable, receipts: receipts)
    let unavailable = try await storage.refresh(vault)
    XCTAssertEqual(unavailable.connection, .sourceUnavailable)
    XCTAssertEqual(unavailable.operations.count, 4)

    let done = TodayBridgeRecordedTask(
      id: fixture.quick.id, title: fixture.quick.title, completed: true, source: .quick)
    let newRows = ["a", "b"].map {
      TodayBridgeRecordedTask(
        id: String(repeating: $0, count: 64), title: "同名任务", completed: false, source: .quick)
    }
    try fixture.publish(vault, tasks: [done] + newRows, receipts: receipts)
    let synced = try await storage.refresh(vault)
    XCTAssertEqual(synced.connection, .connected)
    XCTAssertTrue(synced.operations.isEmpty)
    XCTAssertEqual(synced.tasks.map(\.id), newRows.map(\.id) + [done.id])
    XCTAssertEqual(synced.tasks.filter(\.isPending).count, 0)
    let confirmed = TaskListSections(synced.tasks, completed: \.completed, pending: \.isPending)
    XCTAssertEqual(confirmed.confirmedToDoCount, 2)
    XCTAssertEqual(confirmed.completed.map(\.id), [done.id])
    let collapsedRows =
      newRows.map { TaskListSections<TodayBridgeTask>.Row.ID.task($0.id) } + [.disclosure]
    XCTAssertEqual(confirmed.rows(expanded: false).map(\.id), collapsedRows)
    XCTAssertEqual(confirmed.rows(expanded: true).map(\.id), collapsedRows + [.task(done.id)])
  }

  func testFailuresPersistAndRetryUsesTheCurrentCheckboxWithANewOperationID() async throws {
    let fixture = try fixture()
    let storage = fixture.storage()
    let vault = try await storage.connect(to: fixture.makeVault("Personal"), replacing: nil)
    try fixture.publish(vault, tasks: [fixture.quick])
    let initial = try await storage.refresh(vault)
    let operation = TodayBridgeOperation.targeting(
      initial.tasks[0], day: fixture.day, kind: .delete)
    _ = try await storage.enqueue(operation, for: vault)
    let checked = TodayBridgeRecordedTask(
      id: fixture.quick.id, title: fixture.quick.title, completed: true, source: .quick)
    try fixture.publish(
      vault, tasks: [checked], receipts: [.init(id: operation.id, code: .conflict)])
    let reopened = fixture.storage()
    let failed = try await reopened.refresh(vault)
    XCTAssertTrue(failed.operations.isEmpty)
    XCTAssertEqual(failed.tasks.map(\.completed), [true])
    XCTAssertEqual(failed.failures.map(\.code), [.conflict])
    XCTAssertTrue(try XCTUnwrap(failed.failures.first).canRetry)

    try fixture.publish(vault, tasks: [checked], issue: .sourceUnavailable)
    let temporarilyUnavailable = try await reopened.resolveFailure(
      operation.id, retry: true, for: vault)
    XCTAssertTrue(temporarilyUnavailable.operations.isEmpty)
    XCTAssertEqual(temporarilyUnavailable.failures.map(\.id), [operation.id])
    XCTAssertEqual(temporarilyUnavailable.failures.map(\.canRetry), [false])

    try fixture.publish(vault, tasks: [checked])
    let retried = try await reopened.resolveFailure(operation.id, retry: true, for: vault)
    let next = try XCTUnwrap(retried.operations.first)
    XCTAssertNotEqual(next.id, operation.id)
    XCTAssertEqual(next.taskID, operation.taskID)
    XCTAssertEqual(next.expectedCompleted, true)
    XCTAssertTrue(retried.failures.isEmpty)
    try fixture.publish(
      vault, tasks: [checked], receipts: [.init(id: next.id, code: .unsafeDelete)])
    let rejected = try await reopened.refresh(vault)
    XCTAssertEqual(rejected.failures.map(\.canRetry), [false])
    let dismissed = try await reopened.resolveFailure(next.id, retry: false, for: vault)
    XCTAssertTrue(dismissed.failures.isEmpty)
    XCTAssertTrue(try fixture.client(vault).operations.isEmpty)
  }

  func testChangedTaskAndIncompatibleBoardDoNotDestroyLastReadableSnapshot() async throws {
    let fixture = try fixture()
    let storage = fixture.storage()
    let vault = try await storage.connect(to: fixture.makeVault("Personal"), replacing: nil)
    try fixture.publish(vault, tasks: [fixture.quick])
    let initial = try await storage.refresh(vault)
    let delete = TodayBridgeOperation.targeting(
      initial.tasks[0], day: fixture.day, kind: .delete)
    let renamed = TodayBridgeRecordedTask(
      id: fixture.quick.id, title: "Renamed", completed: false, source: .quick)
    try fixture.publish(vault, tasks: [renamed])
    do {
      _ = try await storage.enqueue(delete, for: vault)
      XCTFail("A stale title should not delete a renamed task")
    } catch {
      XCTAssertEqual(error as? TodayBridgeError, .taskChanged)
    }
    _ = try await storage.refresh(vault)
    try fixture.publish(vault, tasks: [], version: 2)
    let state = try await fixture.storage().refresh(vault)
    XCTAssertEqual(state.connection, .protocolMismatch)
    XCTAssertEqual(state.tasks.map(\.title), ["Renamed"])
    XCTAssertTrue(state.operations.isEmpty)
    let clientFile = fixture.channel(vault).appendingPathComponent("client.json")
    let boardFile = fixture.channel(vault).appendingPathComponent("board.json")
    let clientData = try Data(contentsOf: clientFile)
    let boardData = try Data(contentsOf: boardFile)
    do {
      _ = try await storage.enqueue(.init(kind: .add, title: "New"), for: vault)
      XCTFail("A version mismatch should not accept new mutations")
    } catch {
      XCTAssertEqual(error as? TodayBridgeError, .protocolMismatch)
    }
    XCTAssertEqual(try Data(contentsOf: clientFile), clientData)
    XCTAssertEqual(try Data(contentsOf: boardFile), boardData)
  }

  func testANewDayHidesYesterdaysRowsButKeepsPendingOperations() async throws {
    let fixture = try fixture()
    let storage = fixture.storage()
    let vault = try await storage.connect(to: fixture.makeVault("Personal"), replacing: nil)
    try fixture.publish(vault, tasks: [fixture.quick])
    let initial = try await storage.refresh(vault)
    let toggle = TodayBridgeOperation.targeting(
      initial.tasks[0], day: fixture.day, kind: .complete, completed: true)
    _ = try await storage.enqueue(toggle, for: vault)
    let newTask = TodayBridgeOperation(kind: .add, title: "Carry into today")
    _ = try await storage.enqueue(newTask, for: vault)

    let nextDay = fixture.storage(now: fixture.now.addingTimeInterval(86400))
    let state = try await nextDay.refresh(vault)
    XCTAssertEqual(state.connection, .waiting)
    XCTAssertEqual(state.tasks.map(\.id), [newTask.id])
    XCTAssertEqual(state.operations.map(\.id), [toggle.id, newTask.id])
  }

  func testSyncRejectsSymlinkClientAndLeavesItsTargetUnchanged() async throws {
    let fixture = try fixture()
    let storage = fixture.storage()
    let vault = try await storage.connect(to: fixture.makeVault("Personal"), replacing: nil)
    let client = fixture.channel(vault).appendingPathComponent("client.json")
    let other = fixture.directory.appendingPathComponent("unrelated")
    let original = try Data(contentsOf: client)
    try original.write(to: other)
    try FileManager.default.removeItem(at: client)
    try FileManager.default.createSymbolicLink(at: client, withDestinationURL: other)
    do {
      _ = try await storage.enqueue(.init(kind: .add, title: "No"), for: vault)
      XCTFail("A symlink must not redirect a task operation")
    } catch {
      XCTAssertEqual(error as? TodayBridgeError, .storageUnavailable)
    }
    XCTAssertEqual(try Data(contentsOf: other), original)
  }

  func testControllerRestoresBindingAndQueueAndDisconnectPausesIt() async throws {
    let fixture = try fixture()
    let name = "PulseBridgeTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let bridge = TodayTaskBridge(defaults: defaults, bridgeRoot: fixture.root)
    XCTAssertFalse(bridge.isEnabled)
    try await bridge.connect(to: fixture.makeVault("Personal"))
    XCTAssertTrue(bridge.isEnabled)
    XCTAssertEqual(bridge.connection, .waiting)
    try await bridge.add("  今日任务\n")
    XCTAssertEqual(bridge.pendingCount, 1)
    XCTAssertEqual(bridge.tasks.map(\.title), ["今日任务"])
    XCTAssertFalse(bridge.hasPendingWrite)

    let reopened = TodayTaskBridge(defaults: defaults, bridgeRoot: fixture.root)
    await reopened.refresh()
    XCTAssertEqual(reopened.vaultURL, bridge.vaultURL)
    XCTAssertEqual(reopened.tasks, bridge.tasks)
    try await reopened.disconnect()
    XCTAssertEqual(reopened.connection, .off)
    XCTAssertFalse(reopened.isEnabled)
    let realVault = TodayBridgeVault(canonicalURL: try XCTUnwrap(bridge.vaultURL))
    XCTAssertFalse(try fixture.client(realVault).enabled)
    XCTAssertEqual(try fixture.client(realVault).operations.count, 1)
  }

  func testTodayTaskPaperMeasuresShortListsAndKeepsLongListComposerReachable() async throws {
    let fixture = try fixture()
    let name = "PulseTodayRendering.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let bridge = TodayTaskBridge(defaults: defaults, bridgeRoot: fixture.root, now: { fixture.now })
    try await bridge.connect(to: fixture.makeVault("Today UI"))
    let vault = TodayBridgeVault(canonicalURL: try XCTUnwrap(bridge.vaultURL))
    let completed = TodayBridgeRecordedTask(
      id: fixture.project.id, title: "检查参考看板", completed: true, source: .project)
    try fixture.publish(vault, tasks: [fixture.quick, completed])
    await bridge.refresh()
    XCTAssertEqual(bridge.tasks.map(\.completed), [false, true])

    let presentation = TodayTaskPresentation()
    let localTasks = LocalTaskController(
      store: LocalTaskStore(fileURL: fixture.directory.appendingPathComponent("tasks.json")))
    let localPresentation = LocalTaskPresentation()
    var measurements: [CGFloat?] = []
    let tasks = HomeTaskLists(
      bridge: bridge, presentation: presentation, localTasks: localTasks,
      localPresentation: localPresentation, onEditingChanged: { _ in }, onManageTags: {},
      onTodayHeight: { source, height in
        XCTAssertEqual(source, vault.url)
        measurements.append(height)
      }
    ).background(PulseDesignTokens.background)
    let size = NSSize(width: HomeView.popoverSize.width, height: 360)
    let host = NSHostingView(rootView: tasks.environment(\.locale, Locale(identifier: "en")))
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.ignoresMouseEvents = true
    window.alphaValue = 0
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -16_000, y: -16_000))
    window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(30))
    let shortHeight = try XCTUnwrap(measurements.last?.flatMap { $0 })
    XCTAssertGreaterThan(shortHeight, 130)
    XCTAssertLessThan(shortHeight, size.height)
    window.setContentSize(NSSize(width: size.width, height: shortHeight))

    let wrapped = TodayBridgeRecordedTask(
      id: fixture.quick.id,
      title: String(repeating: "A short Today list can still contain a long title. ", count: 3),
      completed: false, source: .quick)
    measurements.removeAll()
    try fixture.publish(vault, tasks: [wrapped, completed])
    await bridge.refresh()
    for _ in 0..<50 {
      host.layoutSubtreeIfNeeded()
      if let measurement = measurements.last?.flatMap({ $0 }), measurement > shortHeight { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let wrappedHeight = try XCTUnwrap(measurements.last?.flatMap { $0 })
    XCTAssertGreaterThan(wrappedHeight, shortHeight + 12)
    XCTAssertLessThan(wrappedHeight, size.height)
    window.setContentSize(NSSize(width: size.width, height: wrappedHeight))

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseTodayDashboardRender")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
      for language in ["en", "zh-Hans"] {
        host.rootView = tasks.environment(\.locale, Locale(identifier: language))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(
          try XCTUnwrap(bitmap.colorAt(x: 2, y: 2)).alphaComponent, 1, accuracy: 0.01)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
          to: directory.appendingPathComponent("today-\(language)-\(appearance.rawValue).png"))
      }
    }

    let longList = (0..<16).map { index in
      TodayBridgeRecordedTask(
        id: String(format: "%064x", index), title: "Task \(index + 1)",
        completed: false, source: .quick)
    }
    measurements.removeAll()
    try fixture.publish(vault, tasks: longList)
    await bridge.refresh()
    window.setContentSize(size)
    func descendant<T: NSView>(_ type: T.Type, in root: NSView, matching: (T) -> Bool) -> T? {
      if let root = root as? T, matching(root) { return root }
      for child in root.subviews {
        if let result = descendant(type, in: child, matching: matching) { return result }
      }
      return nil
    }
    func focusedComposer() async throws -> NSTextField {
      for _ in 0..<50 {
        host.layoutSubtreeIfNeeded()
        if let field = descendant(
          NSTextField.self, in: host,
          matching: {
            $0.accessibilityIdentifier() == "todayTaskTextField"
          }), field.currentEditor() != nil
        {
          return field
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      return try XCTUnwrap(nil as NSTextField?, "The native Today task field must receive focus.")
    }
    host.layoutSubtreeIfNeeded()
    let field = try XCTUnwrap(descendant(NSTextField.self, in: host) {
      $0.accessibilityIdentifier() == "todayTaskTextField"
    })
    XCTAssertTrue(field.isHidden)
    XCTAssertFalse(field.isEnabled)
    presentation.beginDraft(in: vault.url)
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    XCTAssertTrue(window.firstResponder === editor)
    let firstKey = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: window.windowNumber, context: nil, characters: "a",
      charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
    window.sendEvent(firstKey)
    XCTAssertEqual(editor.string, "a")
    XCTAssertEqual(presentation.drafts[vault.url]?.title, "a")

    let activeField = try await focusedComposer()
    XCTAssertTrue(activeField === field)
    XCTAssertTrue(measurements.contains { $0 == nil }, "Long lists request the full viewport")
    let scroll = try XCTUnwrap(
      descendant(NSScrollView.self, in: host) { ($0.documentView?.frame.height ?? 0) > size.height }
    )
    XCTAssertFalse(field.isDescendant(of: scroll))
    XCTAssertTrue(host.bounds.intersects(field.convert(field.bounds, to: host)))
    editor.setMarkedText("lin", selectedRange: NSRange(location: 3, length: 0),
      replacementRange: NSRange(location: 1, length: 0))
    XCTAssertTrue(editor.hasMarkedText())

    // Crossing the compact measurement threshold must keep the real field
    // editor and its pending input mounted, including the return to a tall list.
    for count in [11, 12] {
      measurements.removeAll()
      try fixture.publish(vault, tasks: Array(longList.prefix(count)))
      await bridge.refresh()
      for _ in 0..<50 {
        host.layoutSubtreeIfNeeded()
        if let report = measurements.last, (report == nil) == (count == 12) { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      let report = try XCTUnwrap(measurements.last)
      if count == 11 {
        XCTAssertGreaterThan(try XCTUnwrap(report), wrappedHeight)
      } else {
        XCTAssertNil(report)
      }
      let activeField = try await focusedComposer()
      XCTAssertTrue(activeField === field)
      XCTAssertTrue(activeField.currentEditor() === editor)
      XCTAssertTrue(editor.hasMarkedText())
      XCTAssertEqual(editor.string, "alin")
      XCTAssertEqual(presentation.drafts[vault.url]?.title, "a")
    }
    editor.insertText("临时任务", replacementRange: NSRange(location: 0, length: 4))
    XCTAssertEqual(presentation.drafts[vault.url]?.title, "临时任务")

    presentation.collapseDraft(in: vault.url)
    host.layoutSubtreeIfNeeded()
    XCTAssertEqual(presentation.drafts[vault.url]?.title, "临时任务")
    XCTAssertNil(presentation.drafts[vault.url]?.focusRequest)
    XCTAssertTrue(field.isHidden)

    presentation.beginDraft(in: vault.url)
    let reopened = try await focusedComposer()
    XCTAssertTrue(reopened === field)
    let reopenedEditor = try XCTUnwrap(reopened.currentEditor() as? NSTextView)
    XCTAssertEqual(reopenedEditor.string, "临时任务")
    reopenedEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    for _ in 0..<50 {
      if !presentation.hasPendingSubmission { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(bridge.pendingCount, 1)
    XCTAssertTrue(bridge.tasks.contains { $0.title == "临时任务" && $0.isPending })
    XCTAssertNil(presentation.drafts[vault.url])
  }

  private func fixture() throws -> BridgeFixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PulseToday-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return BridgeFixture(directory: directory)
  }
}

private struct BridgeFixture {
  let directory: URL
  let now = Date(timeIntervalSince1970: 1_780_000_000)
  let quick = TodayBridgeRecordedTask(
    id: String(repeating: "1", count: 64), title: "Quick", completed: false, source: .quick)
  let project = TodayBridgeRecordedTask(
    id: String(repeating: "2", count: 64), title: "Project", completed: false, source: .project)

  var root: URL { directory.appendingPathComponent("ObsidianToday/v1", isDirectory: true) }
  var day: String { TodayBridgeStorage.dayKey(for: now) }

  func storage(now: Date? = nil) -> TodayBridgeStorage {
    let date = now ?? self.now
    return TodayBridgeStorage(root: root, now: { date })
  }

  func makeVault(_ name: String) throws -> URL {
    let vault = directory.appendingPathComponent(name, isDirectory: true)
    let plugin = vault.appendingPathComponent(
      ".obsidian/plugins/dora-personal-dashboard", isDirectory: true)
    try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
    let manifest = Data(#"{"id":"dora-personal-dashboard","version":"0.6.10"}"#.utf8)
    try manifest.write(to: plugin.appendingPathComponent("manifest.json"))
    return vault
  }

  func channel(_ vault: TodayBridgeVault) -> URL {
    root.appendingPathComponent(vault.id, isDirectory: true)
  }

  func client(_ vault: TodayBridgeVault) throws -> TodayBridgeClientDocument {
    let data = try Data(contentsOf: channel(vault).appendingPathComponent("client.json"))
    return try JSONDecoder().decode(TodayBridgeClientDocument.self, from: data)
  }

  func publish(
    _ vault: TodayBridgeVault, tasks: [TodayBridgeRecordedTask], version: Int = 1,
    issue: TodayBridgeBoardDocument.Issue? = nil, receipts: [TodayBridgeReceipt] = []
  ) throws {
    let snapshot = TodayBridgeBoardDocument(
      version: version, vaultID: vault.id, heartbeat: Int64(now.timeIntervalSince1970 * 1000),
      day: day, tasks: tasks, issue: issue, receipts: receipts)
    let data = try JSONEncoder().encode(snapshot)
    try data.write(to: channel(vault).appendingPathComponent("board.json"), options: .atomic)
  }
}
