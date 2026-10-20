import Foundation

/// User-visible update preferences. They live in the app's ordinary defaults so
/// an update (which only replaces the bundle) keeps them.
@MainActor
final class UpdatePreferences {
  private enum Key {
    static let automaticChecks = "updateAutomaticChecksEnabled"
    static let lastCheckDate = "updateLastCheckDate"
    static let skippedVersion = "updateSkippedVersion"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [Key.automaticChecks: true])
  }

  var automaticallyChecks: Bool {
    get { defaults.bool(forKey: Key.automaticChecks) }
    set { defaults.set(newValue, forKey: Key.automaticChecks) }
  }

  var lastCheckDate: Date? {
    get { defaults.object(forKey: Key.lastCheckDate) as? Date }
    set { defaults.set(newValue, forKey: Key.lastCheckDate) }
  }

  /// A version the user explicitly skipped; it is not offered again until a
  /// different version is published.
  var skippedVersion: String? {
    get { defaults.string(forKey: Key.skippedVersion) }
    set { defaults.set(newValue, forKey: Key.skippedVersion) }
  }
}