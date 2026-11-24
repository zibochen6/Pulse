import Combine
import Foundation

@MainActor
final class AppConfig: ObservableObject {
  private enum Key {
    static let launchAtLoginRequested = "launchAtLoginRequested"
    static let showMenuBarLabel = "showMenuBarLabel"
    static let vipBalanceEnabled = "vipBalanceEnabled"
    static let deepSeekBalanceEnabled = "deepSeekBalanceEnabled"
    static let antigravityEnabled = "antigravityEnabled"
  }

  @Published private(set) var launchAtLoginRequested: Bool
  @Published private(set) var showMenuBarLabel: Bool
  @Published private(set) var vipBalanceEnabled: Bool
  @Published private(set) var deepSeekBalanceEnabled: Bool
  @Published private(set) var antigravityEnabled: Bool
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
    vipBalanceEnabled = defaults.object(forKey: Key.vipBalanceEnabled) as? Bool ?? true
    deepSeekBalanceEnabled = defaults.object(forKey: Key.deepSeekBalanceEnabled) as? Bool ?? true
    antigravityEnabled = defaults.bool(forKey: Key.antigravityEnabled)
    loginItemStatus = loginItemService.status
  }

  func setShowMenuBarLabel(_ enabled: Bool) {
    showMenuBarLabel = enabled
    defaults.set(enabled, forKey: Key.showMenuBarLabel)
  }

  func setVIPBalanceEnabled(_ enabled: Bool) {
    guard vipBalanceEnabled != enabled else { return }
    vipBalanceEnabled = enabled
    defaults.set(enabled, forKey: Key.vipBalanceEnabled)
  }

  func setDeepSeekBalanceEnabled(_ enabled: Bool) {
    guard deepSeekBalanceEnabled != enabled else { return }
    deepSeekBalanceEnabled = enabled
    defaults.set(enabled, forKey: Key.deepSeekBalanceEnabled)
  }

  func setAntigravityEnabled(_ enabled: Bool) {
    guard antigravityEnabled != enabled else { return }
    antigravityEnabled = enabled
    defaults.set(enabled, forKey: Key.antigravityEnabled)
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
      loginItemError = PulseLocalization.format(
        "Could not update Login Items: %@", error.localizedDescription)
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
