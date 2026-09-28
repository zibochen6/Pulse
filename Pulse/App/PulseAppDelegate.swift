import AppKit
import Combine
import SwiftUI

@MainActor
final class PulseAppDelegate: NSObject, NSApplicationDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let config = AppConfig()
  private let usage = UsageController(provider: CodexProvider())
  private let popover = NSPopover()
  private var preferencesSubscription: AnyCancellable?
  private var usageSubscription: AnyCancellable?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    configureStatusItem()
    configurePopover()

    preferencesSubscription = config.$showMenuBarLabel
      .sink { [weak self] showName in
        guard let self else { return }
        self.updateStatusButton(showName: showName, usageState: self.usage.state)
      }
    usageSubscription = usage.$state
      .sink { [weak self] state in
        guard let self else { return }
        self.updateStatusButton(showName: self.config.showMenuBarLabel, usageState: state)
      }
    // The unit test host launches this app; its synthetic tests must not query a real account.
    if Self.shouldStartLiveUsage(environment: ProcessInfo.processInfo.environment) {
      usage.start()
    }
  }

  static func shouldStartLiveUsage(environment: [String: String]) -> Bool {
    environment["PULSE_DISABLE_LIVE_USAGE"] != "1"
  }

  func applicationWillTerminate(_ notification: Notification) {
    usage.stop()
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    button.image = loadMenuBarIcon()
    button.imagePosition = .imageLeading
    button.toolTip = "Pulse · Loading Codex usage"
    button.target = self
    button.action = #selector(togglePopover)
    updateStatusButton(showName: config.showMenuBarLabel, usageState: usage.state)
  }

  private func loadMenuBarIcon() -> NSImage? {
    // The bundled artwork comes from codex-usage-status; see THIRD_PARTY_NOTICES.md.
    let image: NSImage?
    if let url = Bundle.main.url(forResource: "CodexMenuIcon", withExtension: "png"),
      let bundledImage = NSImage(contentsOf: url)
    {
      image = bundledImage
    } else {
      image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Pulse")
    }
    image?.size = NSSize(width: 18, height: 18)
    image?.isTemplate = true
    return image
  }

  private func configurePopover() {
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 360, height: 480)
    popover.contentViewController = NSHostingController(
      rootView: HomeView(config: config, usage: usage, onQuit: { NSApp.terminate(nil) })
    )
  }

  private func updateStatusButton(showName: Bool, usageState: UsageRefreshState) {
    guard let button = statusItem.button else { return }
    let name = showName || button.image == nil ? "Pulse " : ""
    button.attributedTitle = NSAttributedString(
      string: " \(name)\(UsageMenuFormatter.title(for: usageState))",
      attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
    )
    switch usageState {
    case .loading:
      button.toolTip = "Codex usage is loading"
    case .success(let snapshot):
      button.toolTip =
        "Codex usage · updated \(DateFormatter.localizedString(from: snapshot.fetchedAt, dateStyle: .none, timeStyle: .short))"
    case .unavailable(let message), .failure(let message):
      button.toolTip = message
    }
  }

  @objc private func togglePopover() {
    guard let button = statusItem.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      config.refreshLoginItemStatus()
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
  }
}
