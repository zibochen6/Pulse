import Combine
import Foundation

enum TaskSource: String, CaseIterable, Identifiable, Sendable {
  case local
  case apex

  var id: Self { self }
}

/// A missing preference is migrated once; removing a bookmark does not change
/// an explicit choice or delete the user's independent built-in tasks.
@MainActor
final class TaskSourceConfiguration: ObservableObject {
  @Published private(set) var source: TaskSource
  private let defaults: UserDefaults
  private static let sourceKey = "taskSource"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let rawValue = defaults.string(forKey: Self.sourceKey),
      let saved = TaskSource(rawValue: rawValue)
    {
      source = saved
    } else {
      source = defaults.data(forKey: "apexDashboardBookmark") == nil ? .local : .apex
      defaults.set(source.rawValue, forKey: Self.sourceKey)
    }
  }

  func setSource(_ source: TaskSource) {
    defaults.set(source.rawValue, forKey: Self.sourceKey)
    self.source = source
  }
}
