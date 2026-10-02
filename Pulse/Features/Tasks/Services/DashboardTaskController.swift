import Combine
import Foundation

enum DashboardConnectionState: Equatable {
  case notConfigured
  case loading
  case fileMissing
  case permissionDenied
  case readError(String)
  case parseError(String)
  case loaded(Dashboard)
}

struct DashboardTaskSaveFailure: Equatable {
  let message: String
  let needsReselection: Bool
  let task: DashboardTask
  let desiredCompletion: Bool
  let snapshot: Dashboard
}

struct DashboardTaskAddFailure: Equatable {
  let message: String
  let needsReselection: Bool
  let request: DashboardTaskCreationRequest
}

@MainActor
final class DashboardTaskController: ObservableObject {
  @Published private(set) var state: DashboardConnectionState
  @Published private(set) var isRefreshing = false
  @Published private(set) var pendingTaskIDs = Set<UUID>()
  @Published private(set) var saveFailure: DashboardTaskSaveFailure?
  @Published private(set) var isAddingTask = false
  @Published private(set) var addFailure: DashboardTaskAddFailure?
  /// Changes only for an explicit selection/removal, including failed reads.
  /// Presentation owners above navigation can invalidate drafts independently
  /// of whether the newly selected file ever reaches the loaded state.
  @Published private(set) var selectionGeneration = 0

  let configuration: DashboardConfiguration
  private let fileStore: any DashboardFileStoring
  private var issuedRevision = 0
  private var appliedRevision = 0
  private var appliedObservation: ContinuousClock.Instant?

  init(
    configuration: DashboardConfiguration = DashboardConfiguration(),
    parser: ApexDashboardParser = ApexDashboardParser(),
    fileStore: (any DashboardFileStoring)? = nil
  ) {
    self.configuration = configuration
    self.fileStore = fileStore ?? DashboardFileStore(parser: parser)
    state = configuration.hasDashboardSelection ? .loading : .notConfigured
  }

  @discardableResult
  func requestRefresh() -> Task<Void, Never> {
    Task { await refresh() }
  }

  func refresh() async {
    guard !isRefreshing else { return }
    guard configuration.hasDashboardSelection else {
      state = .notConfigured
      return
    }
    let generation = selectionGeneration
    let revision = nextRevision()
    isRefreshing = true
    if case .loaded = state {} else { state = .loading }
    defer { if generation == selectionGeneration { isRefreshing = false } }
    do {
      let url = try configuration.resolveDashboardURL()
      let dashboard = try await fileStore.load(fileURL: url)
      apply(dashboard, generation: generation, revision: revision)
    } catch {
      applyReadError(error, generation: generation, revision: revision)
    }
  }

  /// Register pending synchronously at the click boundary to prevent a second
  /// click from enqueueing before the first asynchronous task starts.
  @discardableResult
  func setCompleted(_ completed: Bool, task: DashboardTask) -> Task<Void, Never>? {
    guard case .loaded(let snapshot) = state,
      let currentTask = snapshot.allTasks.first(where: { $0.id == task.id }),
      currentTask.canToggle, !pendingTaskIDs.contains(task.id)
    else { return nil }
    return startSave(completed, task: currentTask, snapshot: snapshot)
  }

  @discardableResult
  func retrySave() -> Task<Void, Never>? {
    guard let failure = saveFailure, !pendingTaskIDs.contains(failure.task.id) else { return nil }
    // Retry the explicit intent against its original source, never whichever
    // same-text row happens to occupy that position after an external edit.
    return startSave(failure.desiredCompletion, task: failure.task, snapshot: failure.snapshot)
  }

  func dismissSaveFailure() { saveFailure = nil }

  /// The view retains its draft and stable request ID until this returns true.
  /// One add intent at a time; completion of other rows remains available.
  @discardableResult
  func addTask(request: DashboardTaskCreationRequest) -> Task<Bool, Never>? {
    guard !isAddingTask, configuration.hasDashboardSelection else { return nil }
    let generation = selectionGeneration
    let revision = nextRevision()
    isAddingTask = true
    addFailure = nil
    return Task {
      defer { if generation == selectionGeneration { isAddingTask = false } }
      guard generation == selectionGeneration else { return false }
      do {
        let url = try configuration.resolveDashboardURL()
        guard url.standardizedFileURL == request.snapshot.fileURL.standardizedFileURL else {
          throw DashboardWriteError.conflict
        }
        let dashboard = try await fileStore.addTask(request: request, fileURL: url)
        guard generation == selectionGeneration else { return false }
        apply(dashboard, generation: generation, revision: revision)
        addFailure = nil
        return true
      } catch {
        guard generation == selectionGeneration else { return false }
        let failure = error as? DashboardWriteError
        addFailure = DashboardTaskAddFailure(
          message: failure?.localizedDescription
            ?? (error as? DashboardParseError)?.localizedDescription
            ?? "Pulse could not add the task. Refresh or choose the Dashboard again in Settings.",
          needsReselection: failure == .permissionDenied || failure == .fileMissing
            || error is DashboardConfigurationError,
          request: request
        )
        // The replacement may already have persisted before an uncertain flush.
        // Keep the request ID and refresh reality; never overwrite external edits
        // with the original snapshot and never optimistically invent a new row.
        let recoveryRevision = nextRevision()
        do {
          let url = try configuration.resolveDashboardURL()
          let dashboard = try await fileStore.load(fileURL: url)
          apply(dashboard, generation: generation, revision: recoveryRevision)
        } catch {
          applyReadError(error, generation: generation, revision: recoveryRevision)
        }
        return false
      }
    }
  }

  @discardableResult
  func retryAddTask() -> Task<Bool, Never>? {
    guard let request = addFailure?.request else { return nil }
    return addTask(request: request)
  }

  func dismissAddFailure() { addFailure = nil }

  private func startSave(_ completed: Bool, task: DashboardTask, snapshot: Dashboard) -> Task<
    Void, Never
  > {
    let generation = selectionGeneration
    let revision = nextRevision()
    pendingTaskIDs.insert(task.id)
    if saveFailure?.task.id == task.id { saveFailure = nil }
    return Task {
      defer { if generation == selectionGeneration { pendingTaskIDs.remove(task.id) } }
      guard generation == selectionGeneration else { return }
      do {
        let url = try configuration.resolveDashboardURL()
        let dashboard = try await fileStore.setCompleted(
          completed, task: task, snapshot: snapshot, fileURL: url)
        guard generation == selectionGeneration else { return }
        apply(dashboard, generation: generation, revision: revision)
        if saveFailure?.task.id == task.id { saveFailure = nil }
      } catch {
        guard generation == selectionGeneration else { return }
        let failure = error as? DashboardWriteError
        saveFailure = DashboardTaskSaveFailure(
          message: failure?.localizedDescription
            ?? "Pulse could not save this task. Choose the Dashboard again in Settings.",
          needsReselection: failure == .permissionDenied || failure == .fileMissing
            || error is DashboardConfigurationError,
          task: task, desiredCompletion: completed, snapshot: snapshot
        )
        // The attempted byte may already be on disk if flushing/verification
        // failed. Reload reality; never roll back a whole file or assume failure
        // means the task stayed unchecked.
        let recoveryRevision = nextRevision()
        do {
          let url = try configuration.resolveDashboardURL()
          let dashboard = try await fileStore.load(fileURL: url)
          apply(dashboard, generation: generation, revision: recoveryRevision)
        } catch {
          applyReadError(error, generation: generation, revision: recoveryRevision)
        }
      }
    }
  }

  private func nextRevision() -> Int {
    issuedRevision += 1
    return issuedRevision
  }

  private func apply(_ dashboard: Dashboard, generation: Int, revision: Int) {
    guard generation == selectionGeneration else { return }
    if let observation = dashboard.observedAt {
      if let previous = appliedObservation, observation < previous { return }
      appliedObservation = observation
    } else if revision < appliedRevision {
      return
    }
    appliedRevision = max(appliedRevision, revision)
    if case .loaded(let previous) = state {
      state = .loaded(dashboard.preservingIdentities(from: previous))
    } else {
      state = .loaded(dashboard)
    }
  }

  private func applyReadError(_ error: Error, generation: Int, revision: Int) {
    guard generation == selectionGeneration, revision >= appliedRevision else { return }
    appliedRevision = revision
    if let error = error as? DashboardParseError {
      state = .parseError(error.localizedDescription)
    } else if error as? DashboardConfigurationError == .noSelection {
      state = .notConfigured
    } else if error as? DashboardConfigurationError == .couldNotResolveBookmark {
      state = .readError(
        "The Dashboard bookmark is unavailable. Choose the file again in Settings.")
    } else if error as? DashboardConfigurationError == .fileMissing {
      state = .fileMissing
    } else if error as? DashboardConfigurationError == .permissionDenied {
      state = .permissionDenied
    } else {
      switch error as? DashboardWriteError {
      case .fileMissing: state = .fileMissing
      case .permissionDenied: state = .permissionDenied
      default:
        state = .readError(
          (error as? DashboardWriteError)?.localizedDescription
            ?? "Pulse could not read the Dashboard.")
      }
    }
  }

  func saveDashboard(url: URL) async {
    resetSelectionState()
    do {
      try configuration.saveDashboard(url: url)
      state = .loading
      await refresh()
    } catch {
      state = .readError("Pulse could not remember the selected Dashboard file.")
    }
  }

  func removeDashboard() {
    resetSelectionState()
    configuration.clearDashboard()
    state = .notConfigured
  }

  private func resetSelectionState() {
    selectionGeneration += 1
    appliedObservation = nil
    pendingTaskIDs = []
    saveFailure = nil
    isAddingTask = false
    addFailure = nil
    isRefreshing = false
  }
}
