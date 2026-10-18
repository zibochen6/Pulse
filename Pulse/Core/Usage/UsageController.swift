import Combine
import Foundation

@MainActor
final class UsageController: ObservableObject {
  @Published private(set) var state: UsageRefreshState = .loading
  @Published private(set) var isRefreshing = false

  private let provider: any UsageProviding
  private let refreshInterval: Duration
  private var activeRefresh: Task<Void, Never>?
  private var generation = 0
  private var loop: Task<Void, Never>?

  init(provider: any UsageProviding, refreshInterval: Duration = .seconds(60)) {
    self.provider = provider
    self.refreshInterval = refreshInterval
  }

  func start() {
    guard loop == nil else { return }
    loop = Task { [weak self] in
      guard let self else { return }
      await self.refresh()
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: self.refreshInterval)
        } catch {
          break
        }
        guard !Task.isCancelled else { break }
        await self.refresh()
      }
    }
  }

  func stop() {
    loop?.cancel()
    loop = nil
    generation &+= 1
    activeRefresh?.cancel()
    activeRefresh = nil
    isRefreshing = false
  }

  @discardableResult
  func requestRefresh() -> Task<Void, Never> {
    Task { await refresh() }
  }

  /// Refreshes only when no current successful snapshot is recent enough.
  /// This is used by providers whose normal refresh cadence is longer than
  /// a typical popover open/close cycle.
  @discardableResult
  func refreshIfStale(maxAge: TimeInterval, now: Date = Date()) -> Task<Void, Never>? {
    guard !isRefreshing else { return nil }
    if case .success(let snapshot) = state,
      now.timeIntervalSince(snapshot.fetchedAt)
        < (snapshot.hasPartialDataFailure ? min(maxAge, 60) : maxAge)
    {
      return nil
    }
    return requestRefresh()
  }

  /// Changing accounts must clear old money immediately and cannot be dropped
  /// by the normal single-flight guard. Late replies belong to the old generation.
  @discardableResult
  func credentialsDidChange() -> Task<Void, Never> {
    generation &+= 1
    activeRefresh?.cancel()
    activeRefresh = nil
    isRefreshing = false
    state = .loading
    return requestRefresh()
  }

  func refresh() async {
    guard !Task.isCancelled, activeRefresh == nil else { return }
    isRefreshing = true
    let currentGeneration = generation
    let task = Task { await performRefresh(generation: currentGeneration) }
    activeRefresh = task
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private func performRefresh(generation currentGeneration: Int) async {
    defer {
      if currentGeneration == generation {
        activeRefresh = nil
        isRefreshing = false
      }
    }
    guard !Task.isCancelled, currentGeneration == generation else { return }
    // Keep a visible quota steady during a background refresh. A failed fetch
    // still replaces it with an error, so an old value is never shown as current.
    if case .success = state {} else { state = .loading }

    do {
      let snapshot = try await provider.fetch()
      guard !Task.isCancelled, currentGeneration == generation else { return }
      state =
        snapshot.metrics.isEmpty
        ? .unavailable("No usage data is available for this provider.")
        : .success(snapshot)
    } catch is CancellationError {
      return
    } catch let error as UsageFailureDescribing {
      guard !Task.isCancelled, currentGeneration == generation else { return }
      state =
        error.isUnavailable
        ? .unavailable(error.userMessage)
        : .failure(error.userMessage)
    } catch {
      guard !Task.isCancelled, currentGeneration == generation else { return }
      state = .failure("Could not refresh usage. Try again.")
    }
  }
}
