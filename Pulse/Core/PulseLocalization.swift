import Foundation

/// Non-SwiftUI presentation text (native menus, model errors and dynamic
/// labels) uses the same resource table as SwiftUI's localized literals.
/// User-created task/tag text, provider IDs and persistence keys never enter it.
enum PulseLocalization {
  #if DEBUG
    /// Isolated render fixtures can select a language without changing the
    /// user's preferences or introducing shared mutable process state.
    @TaskLocal static var previewLanguage: String?
  #endif

  static func string(_ key: String, bundle: Bundle = .main) -> String {
    #if DEBUG
      let environment = ProcessInfo.processInfo.environment
      let language =
        previewLanguage
        ?? (environment["PULSE_DISABLE_LIVE_USAGE"] == "1"
          ? environment["PULSE_UI_DEMO_LANGUAGE"] : nil)
      if bundle == .main, let language,
        let path = bundle.path(forResource: language, ofType: "lproj"),
        let localizedBundle = Bundle(path: path)
      {
        return localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
      }
    #endif
    return bundle.localizedString(forKey: key, value: key, table: "Localizable")
  }

  static func format(_ key: String, _ arguments: CVarArg..., bundle: Bundle = .main) -> String {
    String(format: string(key, bundle: bundle), locale: Locale.current, arguments: arguments)
  }
}
