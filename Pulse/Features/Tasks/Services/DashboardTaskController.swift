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

@MainActor
final class DashboardTaskController: ObservableObject {
  @Published private(set) var state: DashboardConnectionState
  @Published private(set) var isRefreshing = false

  let configuration: DashboardConfiguration
  private let parser: ApexDashboardParser

  init(
    configuration: DashboardConfiguration = DashboardConfiguration(),
    parser: ApexDashboardParser = ApexDashboardParser()
  ) {
    self.configuration = configuration
    self.parser = parser
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
    isRefreshing = true
    state = .loading
    defer { isRefreshing = false }

    let fileURL: URL
    do {
      fileURL = try configuration.resolveDashboardURL()
    } catch DashboardConfigurationError.noSelection {
      state = .notConfigured
      return
    } catch {
      state = .fileMissing
      return
    }

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      state = .fileMissing
      return
    }
    guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
      state = .permissionDenied
      return
    }

    do {
      let contents = try String(contentsOf: fileURL, encoding: .utf8)
      let snapshot = try await Task.detached(priority: .userInitiated) { [parser] in
        try parser.parse(contents: contents, fileURL: fileURL)
      }.value
      guard !Task.isCancelled else { return }
      state = .loaded(snapshot)
    } catch let error as DashboardParseError {
      guard !Task.isCancelled else { return }
      state = .parseError(error.localizedDescription)
    } catch let error as CocoaError where error.code == .fileReadNoPermission {
      guard !Task.isCancelled else { return }
      state = .permissionDenied
    } catch {
      guard !Task.isCancelled else { return }
      state = .readError("Pulse could not read the selected Dashboard file.")
    }
  }

  func saveDashboard(url: URL) async {
    do {
      try configuration.saveDashboard(url: url)
      await refresh()
    } catch {
      state = .readError("Pulse could not remember the selected Dashboard file.")
    }
  }

  func removeDashboard() {
    configuration.clearDashboard()
    state = .notConfigured
  }
}
