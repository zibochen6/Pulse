import Combine
import Foundation

@MainActor
final class AppConfig: ObservableObject {
  private enum Key {
    static let launchAtLoginRequested = "launchAtLoginRequested"
    static let showMenuBarLabel = "showMenuBarLabel"
  }

  @Published private(set) var launchAtLoginRequested: Bool
  @Published private(set) var showMenuBarLabel: Bool
  @Published private(set) var loginItemStatus: LoginItemStatus
  @Published private(set) var loginItemError: String?

  private let defaults: UserDefaults
  private let loginItemService: any LoginItemManaging

  init(
    defaults: UserDefaults = .standard,
    loginItemService: any LoginItemManaging = SystemLoginItemService()
  ) {
    self.defaults = defaults
    self.loginItemService = loginItemService
    launchAtLoginRequested = defaults.bool(forKey: Key.launchAtLoginRequested)
    showMenuBarLabel = defaults.bool(forKey: Key.showMenuBarLabel)
    loginItemStatus = loginItemService.status
  }

  func setShowMenuBarLabel(_ enabled: Bool) {
    showMenuBarLabel = enabled
    defaults.set(enabled, forKey: Key.showMenuBarLabel)
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    launchAtLoginRequested = enabled
    defaults.set(enabled, forKey: Key.launchAtLoginRequested)
    loginItemError = nil

    do {
      let currentStatus = loginItemService.status
      // The user can also change Login Items in System Settings.
      if (enabled && currentStatus != .enabled) || (!enabled && currentStatus != .notRegistered) {
        try loginItemService.setEnabled(enabled)
      }
    } catch {
      loginItemError = "Could not update Login Items: \(error.localizedDescription)"
    }
    refreshLoginItemStatus()
  }

  func refreshLoginItemStatus() {
    loginItemStatus = loginItemService.status
    if (launchAtLoginRequested && loginItemStatus == .enabled)
      || (!launchAtLoginRequested && loginItemStatus == .notRegistered)
    {
      loginItemError = nil
    }
  }
}
