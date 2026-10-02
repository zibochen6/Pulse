import Combine
import Foundation

struct LocalTaskCompletionFailure: Equatable, Sendable {
  let taskID: UUID
  let completed: Bool
  let message: String
}

@MainActor
final class LocalTaskController: ObservableObject {
  @Published private(set) var document: LocalTaskDocument?
  @Published private(set) var isLoading = false
  @Published private(set) var isSaving = false
  @Published private(set) var pendingTaskIDs = Set<UUID>()
  @Published private(set) var errorMessage: String?
  @Published private(set) var completionFailures: [UUID: LocalTaskCompletionFailure] = [:]

  private let store: any LocalTaskStoring
  private var appliedObservation: ContinuousClock.Instant?
  private var activeSaves = 0
  private var issuedOperation = 0
  private var errorOperation = 0

  init(store: any LocalTaskStoring = LocalTaskStore()) { self.store = store }

  func refresh() async {
    guard !isLoading else { return }
    let operation = nextOperation()
    isLoading = true
    defer { isLoading = false }
    do {
      apply(try await store.load())
      if !isSaving { updateError(nil, operation: operation) }
    } catch { updateError(message(for: error), operation: operation) }
  }

  func tasks(matching filter: LocalTaskFilter) -> [LocalTask] {
    let tasks = document?.tasks ?? []
    switch filter {
    case .all: return tasks
    case .untagged: return tasks.filter { $0.tagIDs.isEmpty }
    case .tag(let id): return tasks.filter { $0.tagIDs.contains(id) }
    }
  }

  func saveTask(
    id: UUID?, text: String, tagIDs: Set<UUID>, newTagNames: [String], creationID: UUID = UUID()
  ) async -> Bool {
    await perform(
      .saveTask(
        id: id, text: text, tagIDs: tagIDs, newTagNames: newTagNames, creationID: creationID))
  }

  /// Register pending at the click boundary; duplicate clicks cannot queue a
  /// second intent before the asynchronous operation begins.
  @discardableResult
  func setCompleted(_ completed: Bool, taskID: UUID) -> Task<Void, Never>? {
    guard document?.tasks.contains(where: { $0.id == taskID }) == true,
      !pendingTaskIDs.contains(taskID)
    else { return nil }
    pendingTaskIDs.insert(taskID)
    let operation = nextOperation()
    beginSaving()
    return Task {
      defer {
        pendingTaskIDs.remove(taskID)
        endSaving()
      }
      _ = await performMutation(
        .setCompleted(taskID: taskID, completed: completed), operation: operation,
        completionIntent: (taskID, completed))
    }
  }

  func deleteTask(id: UUID) async -> Bool {
    let saved = await perform(.deleteTask(id))
    if saved { completionFailures.removeValue(forKey: id) }
    return saved
  }
  func renameTag(id: UUID, name: String) async -> Bool {
    await perform(.renameTag(id: id, name: name))
  }
  func deleteTag(id: UUID) async -> Bool { await perform(.deleteTag(id)) }
  func dismissError() { errorMessage = nil }
  func dismissCompletionFailure(taskID: UUID) { completionFailures.removeValue(forKey: taskID) }

  private func perform(_ mutation: LocalTaskMutation) async -> Bool {
    let operation = nextOperation()
    guard document != nil else {
      updateError(
        "Reload your tasks before making changes. The saved file has not been changed.",
        operation: operation)
      return false
    }
    beginSaving()
    defer { endSaving() }
    return await performMutation(mutation, operation: operation)
  }

  private func performMutation(
    _ mutation: LocalTaskMutation, operation: Int, completionIntent: (UUID, Bool)? = nil
  ) async -> Bool {
    do {
      let snapshot = try await store.mutate(mutation)
      apply(snapshot)
      if let (id, _) = completionIntent {
        completionFailures.removeValue(forKey: id)
      } else {
        updateError(nil, operation: operation)
      }
      return true
    } catch {
      let failureMessage = message(for: error)
      // Verification can fail after replacement. Reload the real state instead
      // of rolling back a file or presenting an unconfirmed in-memory result.
      if let snapshot = try? await store.load() { apply(snapshot) }
      if let (id, completed) = completionIntent {
        completionFailures[id] = LocalTaskCompletionFailure(
          taskID: id, completed: completed, message: failureMessage)
      } else {
        updateError(failureMessage, operation: operation)
      }
      return false
    }
  }

  private func apply(_ snapshot: LocalTaskSnapshot) {
    guard appliedObservation.map({ snapshot.observedAt >= $0 }) ?? true else { return }
    appliedObservation = snapshot.observedAt
    document = snapshot.document
  }

  private func beginSaving() {
    activeSaves += 1
    isSaving = true
  }

  private func endSaving() {
    activeSaves -= 1
    isSaving = activeSaves > 0
  }

  private func message(for error: Error) -> String {
    (error as? LocalTaskStoreError)?.localizedDescription
      ?? "Pulse could not save or read your tasks. Check access and try again."
  }

  private func nextOperation() -> Int {
    issuedOperation += 1
    return issuedOperation
  }

  private func updateError(_ message: String?, operation: Int) {
    guard operation >= errorOperation else { return }
    errorOperation = operation
    errorMessage = message
  }
}
