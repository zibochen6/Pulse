import Foundation

enum TodayBridgeConnection: Equatable, Sendable {
  case off
  case waiting
  case connected
  case sourceUnavailable
  case protocolMismatch
  case storageUnavailable
}

enum TodayBridgeSource: String, Codable, Sendable {
  case quick
  case project
}

struct TodayBridgeTask: Equatable, Identifiable, Sendable {
  let id: String
  let title: String
  var completed: Bool
  let source: TodayBridgeSource
  var isPending: Bool = false
}

enum TodayBridgeReceiptCode: String, Codable, Sendable {
  case applied
  case conflict
  case expired
  case unsafeDelete
  case invalid
}

enum TodayBridgeFailureCode: String, Codable, Sendable {
  case conflict
  case expired
  case unsafeDelete
  case invalid
}

struct TodayBridgeFailure: Equatable, Identifiable, Sendable {
  let id: String
  let title: String
  let code: TodayBridgeFailureCode
  let canRetry: Bool
}

enum TodayBridgeError: LocalizedError, Equatable {
  case invalidVault
  case notConnected
  case storageUnavailable
  case protocolMismatch
  case stillPending
  case emptyTask
  case taskChanged

  var errorDescription: String? {
    switch self {
    case .invalidVault:
      PulseLocalization.string(
        "Choose an Obsidian vault with the Personal Dashboard plugin installed.")
    case .notConnected:
      PulseLocalization.string("Connect an Obsidian vault first.")
    case .storageUnavailable:
      PulseLocalization.string("Pulse could not access the local Obsidian sync files.")
    case .protocolMismatch:
      PulseLocalization.string("The Obsidian sync files use an incompatible version.")
    case .stillPending:
      PulseLocalization.string("This operation is still waiting to sync.")
    case .emptyTask:
      PulseLocalization.string("Enter a task before saving.")
    case .taskChanged:
      PulseLocalization.string("This task no longer exists. Refresh the list and try again.")
    }
  }
}

struct TodayBridgeOperation: Codable, Equatable, Sendable {
  enum Kind: String, Codable, Sendable { case add, complete, delete }

  var id = UUID().uuidString.lowercased()
  let kind: Kind
  var title: String? = nil
  var taskID: String? = nil
  var day: String? = nil
  var expectedTitle: String? = nil
  var expectedCompleted: Bool? = nil
  var completed: Bool? = nil

  var displayTitle: String { title ?? expectedTitle ?? "" }

  static func targeting(
    _ task: TodayBridgeTask, day: String, kind: Kind, completed: Bool? = nil
  ) -> Self {
    Self(
      kind: kind, taskID: task.id, day: day, expectedTitle: task.title,
      expectedCompleted: task.completed, completed: completed)
  }
}

struct TodayBridgeReceipt: Codable, Equatable, Sendable {
  let id: String
  let code: TodayBridgeReceiptCode
}

struct TodayBridgeRejectedOperation: Codable, Equatable, Sendable {
  let operation: TodayBridgeOperation
  let code: TodayBridgeFailureCode
}

struct TodayBridgeRecordedTask: Codable, Equatable, Sendable {
  let id: String
  let title: String
  let completed: Bool
  let source: TodayBridgeSource

  var row: TodayBridgeTask {
    TodayBridgeTask(id: id, title: title, completed: completed, source: source)
  }
}

struct TodayBridgeSnapshot: Codable, Equatable, Sendable {
  let day: String
  let tasks: [TodayBridgeRecordedTask]
}

struct TodayBridgeHeader: Decodable {
  static let version = 1
  let version: Int
  let vaultID: String

  func validate(vaultID expected: String) throws {
    guard version == Self.version, vaultID == expected else {
      throw TodayBridgeError.protocolMismatch
    }
  }
}

struct TodayBridgeClientDocument: Codable, Equatable, Sendable {
  var version = TodayBridgeHeader.version
  let vaultID: String
  var enabled = false
  var operations: [TodayBridgeOperation] = []
  // Pulse-owned fields. The plugin only needs the enabled flag and queue.
  var failures: [TodayBridgeRejectedOperation]? = nil
  var cache: TodayBridgeSnapshot? = nil
}

struct TodayBridgeBoardDocument: Codable, Sendable {
  enum Issue: String, Codable, Sendable {
    case sourceUnavailable
    case protocolMismatch
    case storageUnavailable
  }

  var version = TodayBridgeHeader.version
  let vaultID: String
  let heartbeat: Int64
  var day: String? = nil
  var tasks: [TodayBridgeRecordedTask]? = nil
  var issue: Issue? = nil
  var receipts: [TodayBridgeReceipt] = []

  func snapshot() throws -> TodayBridgeSnapshot? {
    if let day, let tasks {
      guard Set(tasks.map(\.id)).count == tasks.count else {
        throw TodayBridgeError.storageUnavailable
      }
      return TodayBridgeSnapshot(day: day, tasks: tasks)
    }
    guard day == nil, tasks == nil else { throw TodayBridgeError.storageUnavailable }
    return nil
  }

  func connection(on day: String, now: Date) -> TodayBridgeConnection {
    let age = now.timeIntervalSince1970 - Double(heartbeat) / 1000
    guard (-2...12).contains(age) else { return .waiting }
    switch issue {
    case .sourceUnavailable: return .sourceUnavailable
    case .protocolMismatch: return .protocolMismatch
    case .storageUnavailable: return .storageUnavailable
    case nil: return self.day == day && tasks != nil ? .connected : .waiting
    }
  }
}

struct TodayBridgeSessionState: Sendable {
  let day: String?
  let tasks: [TodayBridgeTask]
  let connection: TodayBridgeConnection
  let operations: [TodayBridgeOperation]
  let failures: [TodayBridgeFailure]
  let observedAt = ContinuousClock.now

  init(client: TodayBridgeClientDocument, connection: TodayBridgeConnection, day: String) {
    operations = client.operations
    self.connection = connection
    let snapshot = client.cache.flatMap { $0.day == day ? $0 : nil }
    self.day = snapshot?.day
    let commands = Dictionary(
      client.operations.compactMap { operation in
        operation.taskID.map { ($0, operation) }
      },
      uniquingKeysWith: { first, _ in first })
    let recorded = snapshot?.tasks.map(\.row) ?? []
    let projected: [TodayBridgeTask] = recorded.compactMap { task in
      guard let command = commands[task.id], command.day == day else { return task }
      guard command.kind != .delete else { return nil }
      var pending = task
      pending.completed = command.completed ?? pending.completed
      pending.isPending = true
      return pending
    }
    let newTasks: [TodayBridgeTask] = client.operations.compactMap { command in
      guard command.kind == .add else { return nil }
      return command.title.map {
        TodayBridgeTask(
          id: command.id, title: $0, completed: false, source: .quick, isPending: true)
      }
    }
    tasks = projected + newTasks
    let retryable = Dictionary(
      recorded.filter { commands[$0.id] == nil }.map { ($0.id, $0.title) },
      uniquingKeysWith: { first, _ in first })
    failures = (client.failures ?? []).map { failure in
      let currentTitle = failure.operation.taskID.flatMap { retryable[$0] }
      return TodayBridgeFailure(
        id: failure.operation.id, title: failure.operation.displayTitle, code: failure.code,
        canRetry: connection == .connected && failure.code == .conflict
          && failure.operation.day == day
          && currentTitle != nil && currentTitle == failure.operation.expectedTitle)
    }
  }
}
