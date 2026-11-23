import Darwin
import Foundation

struct TodayBridgeVault: Equatable, Sendable {
  let url: URL
  let id: String

  init(canonicalURL: URL) {
    url = canonicalURL
    id = UpdateChecksum.sha256Hex(
      of: Data(canonicalURL.path.precomposedStringWithCanonicalMapping.utf8))
  }
}

/// The actor owns all Pulse reads and replacements, including acknowledgments.
/// Only the Obsidian plugin writes board.json.
actor TodayBridgeStorage {
  static var defaultRoot: URL {
    LocalTaskStore.defaultFileURL.deletingLastPathComponent()
      .appendingPathComponent("ObsidianToday", isDirectory: true)
      .appendingPathComponent("v1", isDirectory: true)
  }

  private let root: URL
  private let now: @Sendable () -> Date
  private let files = FileManager.default

  init(root: URL, now: @escaping @Sendable () -> Date = { Date() }) {
    self.root = root
    self.now = now
  }

  func connect(to selection: URL, replacing previous: TodayBridgeVault?) throws -> TodayBridgeVault
  {
    let vault = try resolveVault(selection)
    var next = try loadClient(vault) ?? TodayBridgeClientDocument(vaultID: vault.id)
    try prepare(vault)
    let old = previous.flatMap { $0.id == vault.id ? nil : $0 }
    let previousClient = try old.flatMap(loadClient)
    if let old, var paused = previousClient, paused.enabled {
      paused.enabled = false
      try writeClient(paused, for: old)
    }
    do {
      if !next.enabled {
        next.enabled = true
        try writeClient(next, for: vault)
      }
    } catch {
      if let old, let previousClient, previousClient.enabled {
        try? writeClient(previousClient, for: old)
      }
      throw error
    }
    return vault
  }

  func disconnect(_ vault: TodayBridgeVault) throws {
    guard var client = try loadClient(vault), client.enabled else { return }
    client.enabled = false
    try writeClient(client, for: vault)
  }

  func refresh(_ vault: TodayBridgeVault) throws -> TodayBridgeSessionState {
    try update(vault)
  }

  func enqueue(_ operation: TodayBridgeOperation, for vault: TodayBridgeVault) throws
    -> TodayBridgeSessionState
  {
    try update(vault) { client, day, connection in
      if connection == .protocolMismatch { throw TodayBridgeError.protocolMismatch }
      if connection == .storageUnavailable { throw TodayBridgeError.storageUnavailable }
      try Self.append(operation, to: &client, day: day)
    }
  }

  func resolveFailure(_ id: String, retry: Bool, for vault: TodayBridgeVault) throws
    -> TodayBridgeSessionState
  {
    try update(vault) { client, day, connection in
      guard let failure = client.failures?.first(where: { $0.operation.id == id }) else { return }
      if retry {
        // A failed command needs a new expectation from the live board.
        // Keep it available for review when a connection drops mid-click.
        guard connection == .connected else { return }
        let original = failure.operation
        guard failure.code == .conflict, original.day == day, client.cache?.day == day,
          let task = client.cache?.tasks.first(where: {
            $0.id == original.taskID && $0.title == original.expectedTitle
          })
        else { throw TodayBridgeError.taskChanged }
        let next = TodayBridgeOperation.targeting(
          task.row, day: day, kind: original.kind, completed: original.completed)
        try Self.append(next, to: &client, day: day)
      }
      client.failures?.removeAll { $0.operation.id == id }
      if client.failures?.isEmpty == true { client.failures = nil }
    }
  }

  private static func append(
    _ operation: TodayBridgeOperation, to client: inout TodayBridgeClientDocument, day: String
  ) throws {
    if let target = operation.taskID {
      guard operation.day == day, client.cache?.day == day,
        client.cache?.tasks.contains(where: {
          $0.id == target && $0.title == operation.expectedTitle
            && $0.completed == operation.expectedCompleted
        }) == true
      else { throw TodayBridgeError.taskChanged }
      guard !client.operations.contains(where: { $0.taskID == target }) else {
        throw TodayBridgeError.stillPending
      }
    }
    client.operations.append(operation)
  }

  private func update(
    _ vault: TodayBridgeVault,
    change: (inout TodayBridgeClientDocument, String, TodayBridgeConnection) throws -> Void = {
      _, _, _ in
    }
  ) throws -> TodayBridgeSessionState {
    guard let original = try loadClient(vault), original.enabled else {
      throw TodayBridgeError.notConnected
    }
    let date = now()
    let day = Self.dayKey(for: date)
    var client = original
    var connection: TodayBridgeConnection = .waiting
    do {
      if let data = try read("board.json", in: vault) {
        let decoder = JSONDecoder()
        try decoder.decode(TodayBridgeHeader.self, from: data).validate(vaultID: vault.id)
        let board = try decoder.decode(TodayBridgeBoardDocument.self, from: data)
        let snapshot = try board.snapshot()
        connection = board.connection(on: day, now: date)
        if let snapshot, board.issue == nil || client.cache == nil {
          client.cache = snapshot
        }
        Self.acknowledge(board, in: &client)
      }
    } catch TodayBridgeError.protocolMismatch {
      connection = .protocolMismatch
    } catch {
      connection = .storageUnavailable
    }

    try change(&client, day, connection)
    if client != original { try writeClient(client, for: vault) }
    return TodayBridgeSessionState(client: client, connection: connection, day: day)
  }

  private static func acknowledge(
    _ board: TodayBridgeBoardDocument, in client: inout TodayBridgeClientDocument
  ) {
    guard !board.receipts.isEmpty, !client.operations.isEmpty else { return }
    let codes = Dictionary(
      board.receipts.map { ($0.id, $0.code) }, uniquingKeysWith: { first, _ in first })
    var pending: [TodayBridgeOperation] = []
    var failures = client.failures ?? []
    for operation in client.operations {
      switch codes[operation.id] {
      case nil:
        pending.append(operation)
      case .applied:
        // Keep the overlay until a readable snapshot has caught up to the write.
        if board.issue != nil || board.tasks == nil { pending.append(operation) }
      case .some(let code):
        if let failure = TodayBridgeFailureCode(rawValue: code.rawValue) {
          failures.append(TodayBridgeRejectedOperation(operation: operation, code: failure))
        }
      }
    }
    client.operations = pending
    client.failures = failures.isEmpty ? nil : failures
  }

  private func resolveVault(_ selection: URL) throws -> TodayBridgeVault {
    guard selection.isFileURL, let canonical = realpath(selection.path, nil) else {
      throw TodayBridgeError.invalidVault
    }
    defer { free(canonical) }
    let url = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
    let manifest = url.appendingPathComponent(
      ".obsidian/plugins/dora-personal-dashboard/manifest.json")
    struct Manifest: Decodable { let id: String }
    guard let data = try? Data(contentsOf: manifest),
      let plugin = try? JSONDecoder().decode(Manifest.self, from: data),
      plugin.id == "dora-personal-dashboard"
    else { throw TodayBridgeError.invalidVault }
    return TodayBridgeVault(canonicalURL: url)
  }

  private func loadClient(_ vault: TodayBridgeVault) throws -> TodayBridgeClientDocument? {
    guard let data = try read("client.json", in: vault) else { return nil }
    let decoder = JSONDecoder()
    do {
      try decoder.decode(TodayBridgeHeader.self, from: data).validate(vaultID: vault.id)
      let client = try decoder.decode(TodayBridgeClientDocument.self, from: data)
      let taskIDs = client.cache?.tasks.map(\.id) ?? []
      guard Set(taskIDs).count == taskIDs.count else { throw TodayBridgeError.storageUnavailable }
      return client
    } catch let error as TodayBridgeError {
      throw error
    } catch {
      throw TodayBridgeError.storageUnavailable
    }
  }

  private func writeClient(_ client: TodayBridgeClientDocument, for vault: TodayBridgeVault) throws
  {
    let directory = try prepare(vault)
    let url = directory.appendingPathComponent("client.json")
    _ = try checkRegularFile(url)
    do {
      let data = try JSONEncoder().encode(client)
      try data.write(to: url, options: .atomic)
    } catch {
      throw TodayBridgeError.storageUnavailable
    }
  }

  private func read(_ filename: String, in vault: TodayBridgeVault) throws -> Data? {
    let directory = channelDirectory(vault)
    for folder in [root.deletingLastPathComponent(), root, directory] {
      guard try checkPrivateDirectory(folder) else { return nil }
    }
    let url = directory.appendingPathComponent(filename)
    guard try checkRegularFile(url) else { return nil }
    do {
      return try Data(contentsOf: url)
    } catch {
      throw TodayBridgeError.storageUnavailable
    }
  }

  @discardableResult
  private func prepare(_ vault: TodayBridgeVault) throws -> URL {
    let directory = channelDirectory(vault)
    for folder in [root.deletingLastPathComponent(), root, directory] {
      if try !checkPrivateDirectory(folder) {
        do {
          try files.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
          throw TodayBridgeError.storageUnavailable
        }
        guard try checkPrivateDirectory(folder) else { throw TodayBridgeError.storageUnavailable }
      }
    }
    return directory
  }

  private func channelDirectory(_ vault: TodayBridgeVault) -> URL {
    root.appendingPathComponent(vault.id, isDirectory: true)
  }

  private func checkPrivateDirectory(_ url: URL) throws -> Bool {
    guard let item = try fileStat(url) else { return false }
    guard item.st_mode & S_IFMT == S_IFDIR, item.st_mode & 0o077 == 0 else {
      throw TodayBridgeError.storageUnavailable
    }
    return true
  }

  private func checkRegularFile(_ url: URL) throws -> Bool {
    guard let item = try fileStat(url) else { return false }
    guard item.st_mode & S_IFMT == S_IFREG else { throw TodayBridgeError.storageUnavailable }
    return true
  }

  private func fileStat(_ url: URL) throws -> stat? {
    var item = stat()
    guard lstat(url.path, &item) == 0 else {
      if errno == ENOENT { return nil }
      throw TodayBridgeError.storageUnavailable
    }
    guard item.st_uid == geteuid() else { throw TodayBridgeError.storageUnavailable }
    return item
  }

  static func dayKey(for date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
}
