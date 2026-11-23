import Combine
import Foundation

@MainActor
final class TodayTaskBridge: ObservableObject {
  private static let vaultPreference = "todayBridgeVaultPath"

  @Published private(set) var vaultURL: URL?
  @Published private(set) var tasks: [TodayBridgeTask] = []
  @Published private(set) var connection: TodayBridgeConnection = .off
  @Published private(set) var pendingCount = 0
  @Published private(set) var failures: [TodayBridgeFailure] = []
  @Published private(set) var hasPendingWrite = false

  var isEnabled: Bool { vaultURL != nil }

  private let defaults: UserDefaults
  private let storage: TodayBridgeStorage
  private var vault: TodayBridgeVault?
  private var day: String?
  private var lastObserved: ContinuousClock.Instant?
  private var polling: Task<Void, Never>?
  private var configurationInFlight = false
  private var generation = 0
  private var writes = 0

  init(
    defaults: UserDefaults = .standard, bridgeRoot: URL = TodayBridgeStorage.defaultRoot,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.defaults = defaults
    storage = TodayBridgeStorage(root: bridgeRoot, now: now)
    if let path = defaults.string(forKey: Self.vaultPreference) {
      let url = URL(fileURLWithPath: path, isDirectory: true)
      vault = TodayBridgeVault(canonicalURL: url)
      vaultURL = url
      connection = .waiting
    }
  }

  deinit { polling?.cancel() }

  func start() {
    guard vault != nil, polling == nil else { return }
    polling = Task { [weak self] in
      while !Task.isCancelled {
        await self?.refresh()
        do {
          try await Task.sleep(for: .milliseconds(750))
        } catch {
          return
        }
      }
    }
  }

  func connect(to selection: URL) async throws {
    try beginConfiguration()
    defer { endConfiguration() }
    let selected = try await storage.connect(to: selection, replacing: vault)
    defaults.set(selected.url.path, forKey: Self.vaultPreference)
    if selected != vault { reset(to: selected) }
    await refreshSelection(selected, generation: generation)
    start()
  }

  func disconnect() async throws {
    try beginConfiguration()
    defer { endConfiguration() }
    if let vault { try await storage.disconnect(vault) }
    defaults.removeObject(forKey: Self.vaultPreference)
    polling?.cancel()
    polling = nil
    reset(to: nil)
  }

  func refresh() async {
    guard let vault, !configurationInFlight else { return }
    await refreshSelection(vault, generation: generation)
  }

  func add(_ title: String) async throws {
    let text = title.components(separatedBy: .newlines).joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw TodayBridgeError.emptyTask }
    try await enqueue(TodayBridgeOperation(kind: .add, title: text))
  }

  func setCompleted(_ completed: Bool, taskID: String) async throws {
    let (task, day) = try target(taskID)
    guard task.completed != completed else { return }
    try await enqueue(.targeting(task, day: day, kind: .complete, completed: completed))
  }

  func delete(taskID: String) async throws {
    let (task, day) = try target(taskID)
    try await enqueue(.targeting(task, day: day, kind: .delete))
  }

  func retry(_ failureID: String) async throws {
    try await write { storage, vault in
      try await storage.resolveFailure(failureID, retry: true, for: vault)
    }
  }

  func dismissFailure(_ failureID: String) async throws {
    try await write { storage, vault in
      try await storage.resolveFailure(failureID, retry: false, for: vault)
    }
  }

  private func refreshSelection(_ vault: TodayBridgeVault, generation: Int) async {
    do {
      apply(try await storage.refresh(vault), generation: generation)
    } catch {
      guard generation == self.generation else { return }
      let next: TodayBridgeConnection =
        (error as? TodayBridgeError) == .protocolMismatch ? .protocolMismatch : .storageUnavailable
      if next != connection { connection = next }
    }
  }

  private func enqueue(_ operation: TodayBridgeOperation) async throws {
    guard connection != .protocolMismatch else { throw TodayBridgeError.protocolMismatch }
    try await write { storage, vault in try await storage.enqueue(operation, for: vault) }
  }

  private func target(_ taskID: String) throws -> (TodayBridgeTask, String) {
    guard let day, let task = tasks.first(where: { $0.id == taskID }) else {
      throw TodayBridgeError.taskChanged
    }
    guard !task.isPending else { throw TodayBridgeError.stillPending }
    return (task, day)
  }

  private func write(
    _ change: (TodayBridgeStorage, TodayBridgeVault) async throws -> TodayBridgeSessionState
  ) async throws {
    guard let vault else { throw TodayBridgeError.notConnected }
    guard !configurationInFlight else { throw TodayBridgeError.stillPending }
    let generation = generation
    beginWrite()
    defer { endWrite() }
    do {
      apply(try await change(storage, vault), generation: generation)
    } catch {
      await refresh()
      throw error
    }
  }

  private func apply(_ state: TodayBridgeSessionState, generation: Int) {
    guard generation == self.generation,
      lastObserved.map({ state.observedAt >= $0 }) ?? true
    else { return }
    lastObserved = state.observedAt
    day = state.day
    if state.connection != connection { connection = state.connection }
    if state.tasks != tasks { tasks = state.tasks }
    if state.operations.count != pendingCount { pendingCount = state.operations.count }
    if state.failures != failures { failures = state.failures }
  }

  private func reset(to vault: TodayBridgeVault?) {
    generation += 1
    self.vault = vault
    vaultURL = vault?.url
    connection = vault == nil ? .off : .waiting
    day = nil
    tasks = []
    pendingCount = 0
    failures = []
    lastObserved = nil
  }

  private func beginConfiguration() throws {
    guard !hasPendingWrite else { throw TodayBridgeError.stillPending }
    configurationInFlight = true
    beginWrite()
  }

  private func endConfiguration() {
    configurationInFlight = false
    endWrite()
  }

  private func beginWrite() {
    writes += 1
    if writes == 1 { hasPendingWrite = true }
  }

  private func endWrite() {
    writes -= 1
    if writes == 0 { hasPendingWrite = false }
  }
}
