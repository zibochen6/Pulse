import Combine
import Foundation

/// Enough information to repeat a failed completion faithfully. Repeating tasks
/// also carry the intended completion instant, so a retry after midnight still
/// records the day the user clicked instead of silently moving to today.
struct LocalTaskCompletionFailure: Equatable, Sendable {
  let taskID: UUID
  let completed: Bool
  let repeatsDaily: Bool
  let completedAt: Date
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
    matching(document?.tasks ?? [], filter: filter)
  }

  /// Open tasks for the current filter, in stored order. Kept as a helper so the
  /// list can show open tasks before completed ones without re-deriving the
  /// filter in the view.
  func incompleteTasks(matching filter: LocalTaskFilter) -> [LocalTask] {
    tasks(matching: filter).filter { !$0.completed }
  }

  func completedTasks(matching filter: LocalTaskFilter) -> [LocalTask] {
    tasks(matching: filter).filter(\.completed)
  }

  func saveTask(
    id: UUID?, text: String, tagIDs: Set<UUID>, newTagNames: [String], repeatsDaily: Bool = false,
    creationID: UUID = UUID()
  ) async -> Bool {
    await perform(
      .saveTask(
        id: id, text: text, tagIDs: tagIDs, newTagNames: newTagNames, repeatsDaily: repeatsDaily,
        creationID: creationID))
  }

  /// Register pending at the click boundary; duplicate clicks cannot queue a
  /// second intent before the asynchronous operation begins.
  @discardableResult
  func setCompleted(_ completed: Bool, taskID: UUID) -> Task<Void, Never>? {
    // The click is the moment that matters; capture it before the queued
    // mutation runs so a slow save cannot shift a daily completion to the
    // next day.
    performCompletion(completed, taskID: taskID, completedAt: .now)
  }

  /// Retries a failed completion with the data recorded for it, so a repeating
  /// task keeps its original day instead of moving to the retry's day.
  @discardableResult
  func retryCompletion(_ failure: LocalTaskCompletionFailure) -> Task<Void, Never>? {
    guard failure.completed, failure.repeatsDaily else {
      return setCompleted(failure.completed, taskID: failure.taskID)
    }
    return performCompletion(true, taskID: failure.taskID, completedAt: failure.completedAt)
  }

  /// Re-arms daily tasks completed on an earlier day. Safe to call every time
  /// the popover opens: the store short-circuits when nothing is stale.
  ///
  /// This is background maintenance rather than a user save, so it never raises
  /// `isSaving` (which would disable typing mid-composition) and it never clears
  /// a failure the user still has to act on.
  func resetRepeatingTasks() async {
    guard document != nil else { return }
    let operation = nextOperation()
    _ = await performMutation(
      .resetRepeatingTasks(today: .now), operation: operation, clearsError: false)
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

  /// Shared completion path used by clicks and by recorded retries, so both
  /// reserve the pending marker and pick the same store mutation.
  private func performCompletion(_ completed: Bool, taskID: UUID, completedAt: Date) -> Task<
    Void, Never
  >? {
    guard let task = document?.tasks.first(where: { $0.id == taskID }),
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
      // Daily completion goes through `.completeRepeating`, which records the
      // day and is idempotent within it; un-completing uses the plain mutation.
      let mutation: LocalTaskMutation
      if completed && task.repeatsDaily {
        mutation = .completeRepeating(taskID: taskID, completedAt: completedAt)
      } else {
        mutation = .setCompleted(taskID: taskID, completed: completed)
      }
      _ = await performMutation(
        mutation, operation: operation,
        completionIntent: LocalTaskCompletionIntent(
          taskID: taskID, completed: completed, repeatsDaily: task.repeatsDaily,
          completedAt: completedAt))
    }
  }

  private func matching(_ tasks: [LocalTask], filter: LocalTaskFilter) -> [LocalTask] {
    switch filter {
    case .all: return tasks
    case .untagged: return tasks.filter { $0.tagIDs.isEmpty }
    case .tag(let id): return tasks.filter { $0.tagIDs.contains(id) }
    }
  }

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
    _ mutation: LocalTaskMutation, operation: Int,
    completionIntent: LocalTaskCompletionIntent? = nil, clearsError: Bool = true
  ) async -> Bool {
    do {
      let snapshot = try await store.mutate(mutation)
      apply(snapshot)
      if let intent = completionIntent {
        completionFailures.removeValue(forKey: intent.taskID)
      } else if clearsError {
        updateError(nil, operation: operation)
      }
      return true
    } catch {
      let failureMessage = message(for: error)
      // Verification can fail after replacement. Reload the real state instead
      // of rolling back a file or presenting an unconfirmed in-memory result.
      if let snapshot = try? await store.load() { apply(snapshot) }
      if let intent = completionIntent {
        completionFailures[intent.taskID] = LocalTaskCompletionFailure(
          taskID: intent.taskID, completed: intent.completed, repeatsDaily: intent.repeatsDaily,
          completedAt: intent.completedAt, message: failureMessage)
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

/// What the user asked for, independent of which store mutation carried it.
private struct LocalTaskCompletionIntent: Sendable {
  let taskID: UUID
  let completed: Bool
  let repeatsDaily: Bool
  let completedAt: Date
}
