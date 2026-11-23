import Foundation
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
    XCTAssertEqual(queued.tasks.map(\.id), [fixture.quick.id, first.id, second.id])
    XCTAssertEqual(queued.tasks.map(\.isPending), [true, true, true])
    XCTAssertTrue(try XCTUnwrap(queued.tasks.first).completed)

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
    XCTAssertEqual(synced.tasks.map(\.id), [done.id] + newRows.map(\.id))
    XCTAssertEqual(synced.tasks.filter(\.isPending).count, 0)
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
