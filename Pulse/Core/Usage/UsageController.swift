import Combine
import Foundation

@MainActor
final class UsageController: ObservableObject {
  @Published private(set) var state: UsageRefreshState = .loading
  @Published private(set) var isRefreshing = false

  private let provider: any UsageProviding
  private let refreshInterval: Duration
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
  }

  func requestRefresh() {
    Task { await refresh() }
  }

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    // Keep a visible quota steady during a background refresh. A failed fetch
    // still replaces it with an error, so an old value is never shown as current.
    if case .success = state {} else { state = .loading }
    defer { isRefreshing = false }

    do {
      let snapshot = try await provider.fetch()
      guard !Task.isCancelled else { return }
      state =
        snapshot.metrics.isEmpty
        ? .unavailable("No usage data is available for this provider.")
        : .success(snapshot)
    } catch is CancellationError {
      return
    } catch let error as UsageFailureDescribing {
      guard !Task.isCancelled else { return }
      state =
        error.isUnavailable
        ? .unavailable(error.userMessage)
        : .failure(error.userMessage)
    } catch {
      guard !Task.isCancelled else { return }
      state = .failure("Could not refresh usage. Try again.")
    }
  }
}
