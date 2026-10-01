import Combine
import Foundation

enum DashboardConfigurationError: LocalizedError, Equatable {
  case noSelection
  case couldNotSaveBookmark
  case couldNotResolveBookmark
  case fileMissing
  case permissionDenied

  var errorDescription: String? {
    switch self {
    case .noSelection:
      "No Apex Dashboard file has been selected."
    case .couldNotSaveBookmark:
      "Pulse could not remember the selected Dashboard file."
    case .couldNotResolveBookmark:
      "Pulse could not locate the selected Dashboard file."
    case .fileMissing:
      "The selected Dashboard file was moved or deleted."
    case .permissionDenied:
      "Pulse no longer has permission to access the selected Dashboard file."
    }
  }
}

/// Persists a selected Dashboard without recording its path or task content.
@MainActor
final class DashboardConfiguration: ObservableObject {
  private enum Key {
    static let dashboardBookmark = "apexDashboardBookmark"
  }

  @Published private(set) var hasDashboardSelection: Bool
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    hasDashboardSelection = defaults.data(forKey: Key.dashboardBookmark) != nil
  }

  func saveDashboard(url: URL) throws {
    let bookmark: Data
    do {
      bookmark = try url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil
      )
    } catch {
      throw DashboardConfigurationError.couldNotSaveBookmark
    }
    defaults.set(bookmark, forKey: Key.dashboardBookmark)
    hasDashboardSelection = true
  }

  func resolveDashboardURL() throws -> URL {
    guard let bookmark = defaults.data(forKey: Key.dashboardBookmark) else {
      throw DashboardConfigurationError.noSelection
    }
    var isStale = false
    let url: URL
    do {
      url = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
    } catch {
      let underlying = error as NSError
      if underlying.domain == NSCocoaErrorDomain {
        if underlying.code == NSFileNoSuchFileError || underlying.code == NSFileReadNoSuchFileError
        {
          throw DashboardConfigurationError.fileMissing
        }
        if underlying.code == NSFileReadNoPermissionError {
          throw DashboardConfigurationError.permissionDenied
        }
      }
      throw DashboardConfigurationError.couldNotResolveBookmark
    }
    if isStale {
      try saveDashboard(url: url)
    }
    return url
  }

  func clearDashboard() {
    defaults.removeObject(forKey: Key.dashboardBookmark)
    hasDashboardSelection = false
  }
}
