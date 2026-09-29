import AppKit
import Combine
import SwiftUI

@MainActor
final class PulseAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let config = AppConfig()
  private let usage = UsageController(provider: CodexProvider())
  private let vipConfiguration = VIPConfiguration()
  private let vipUsage = UsageController(provider: VIPProvider(), refreshInterval: .seconds(600))
  private let pages = PopoverPageController()
  private let popover = NSPopover()
  private var preferencesSubscription: AnyCancellable?
  private var usageSubscription: AnyCancellable?
  private lazy var hoverController = PopoverHoverController(
    pointerPresence: { [weak self] in
      self?.pointerPresence()
        ?? PopoverPointerPresence(statusButton: false, content: false, popoverWindow: false)
    },
    close: { [weak self] in self?.popover.performClose(nil) }
  )
  private lazy var statusTrackingOwner = PopoverPointerTrackingOwner(
    onEnter: { [weak self] in
      guard let self, self.popover.isShown else { return }
      self.hoverController.entered(.statusButton)
    },
    onExit: { [weak self] in
      guard let self, self.popover.isShown else { return }
      self.hoverController.exited(.statusButton)
    }
  )
  private lazy var contentTrackingOwner = PopoverPointerTrackingOwner(
    onEnter: { [weak self] in
      guard let self, self.popover.isShown else { return }
      self.hoverController.entered(.content)
    },
    onExit: { [weak self] in
      guard let self, self.popover.isShown else { return }
      self.hoverController.exited(.content)
    }
  )

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
      vipUsage.start()
    }
  }

  static func shouldStartLiveUsage(environment: [String: String]) -> Bool {
    environment["PULSE_DISABLE_LIVE_USAGE"] != "1"
  }

  func applicationWillTerminate(_ notification: Notification) {
    usage.stop()
    vipUsage.stop()
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    button.image = loadMenuBarIcon()
    button.imagePosition = .imageLeading
    button.toolTip = "Pulse · Loading Codex usage"
    button.target = self
    button.action = #selector(togglePopover)
    installTrackingArea(on: button, owner: statusTrackingOwner)
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
    popover.delegate = self
    // A frequently opened menu bar panel should appear immediately. The default
    // popover fade exposed the desktop through SwiftUI's former clear background.
    popover.animates = false
    popover.contentSize = HomeView.popoverSize
    let hostingController = NSHostingController(
      rootView: HomeView(
        config: config,
        usage: usage,
        vipUsage: vipUsage,
        vipConfiguration: vipConfiguration,
        pages: pages,
        onVIPCredentialsChanged: { [weak self] in self?.vipUsage.requestRefresh() },
        onQuit: { NSApp.terminate(nil) }
      )
    )
    popover.contentViewController = hostingController
    installTrackingArea(on: hostingController.view, owner: contentTrackingOwner)
  }

  private func installTrackingArea(on view: NSView, owner: PopoverPointerTrackingOwner) {
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: owner,
      userInfo: nil
    )
    view.addTrackingArea(area)
  }

  private func pointerPresence() -> PopoverPointerPresence {
    let contentView = popover.contentViewController?.view
    return PopoverPointerPresence(
      statusButton: pointerInside(statusItem.button),
      content: pointerInside(contentView),
      popoverWindow: contentView?.window?.frame.contains(NSEvent.mouseLocation) ?? false
    )
  }

  private func pointerInside(_ view: NSView?) -> Bool {
    guard let view, let window = view.window else { return false }
    let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
    return rect.contains(NSEvent.mouseLocation)
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
      vipUsage.refreshIfStale(maxAge: 600)
      pages.reset()
      hoverController.beginOpening()
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      let presence = pointerPresence()
      hoverController.synchronize(statusButton: presence.statusButton, content: presence.content)
    }
  }

  func popoverDidClose(_ notification: Notification) {
    hoverController.reset()
    pages.reset()
  }
}
