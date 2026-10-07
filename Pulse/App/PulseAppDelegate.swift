import AppKit
import Combine
import SwiftUI

@MainActor
final class PulseAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  // The XCTest host must not migrate the real user's source preference or use
  // their local task file. Production always uses the normal preferences.
  private static let runtimeDefaults: UserDefaults = {
    guard ProcessInfo.processInfo.environment["PULSE_DISABLE_LIVE_USAGE"] == "1" else {
      return .standard
    }
    guard
      let defaults = UserDefaults(
        suiteName: "Pulse.TestHost.\(ProcessInfo.processInfo.processIdentifier)")
    else {
      preconditionFailure("Could not create isolated test-host preferences")
    }
    return defaults
  }()

  private let config = AppConfig(defaults: PulseAppDelegate.runtimeDefaults)
  private let usage = UsageController(provider: CodexProvider())
  private let vipConfiguration = VIPConfiguration()
  private let vipUsage = UsageController(provider: VIPProvider(), refreshInterval: .seconds(600))
  private let tasks = DashboardTaskController(
    configuration: DashboardConfiguration(defaults: PulseAppDelegate.runtimeDefaults))
  private let localTasks = LocalTaskController(
    store: LocalTaskStore(
      fileURL:
        ProcessInfo.processInfo.environment["PULSE_DISABLE_LIVE_USAGE"] == "1"
        ? FileManager.default.temporaryDirectory.appendingPathComponent(
          "PulseTestHost-\(ProcessInfo.processInfo.processIdentifier)/tasks.json")
        : LocalTaskStore.defaultFileURL))
  private let taskSource = TaskSourceConfiguration(defaults: PulseAppDelegate.runtimeDefaults)
  private var taskEditorActive = false
  private let pages = PopoverPageController()
  private let popover = NSPopover()
  private var preferencesSubscription: AnyCancellable?
  private var usageSubscription: AnyCancellable?
  private var motionPreferencesSubscription: AnyCancellable?
  private lazy var hoverController = PopoverHoverController(
    pointerPresence: { [weak self] in
      self?.pointerPresence()
        ?? PopoverPointerPresence(statusButton: false, content: false, popoverWindow: false)
    },
    close: { [weak self] in self?.popover.performClose(nil) }
  )
  private lazy var dashboardPicker = DashboardFilePicker(
    closePopover: { [weak self] in
      guard let self else { return false }
      guard self.popover.isShown || self.isPopoverWindowVisible else { return false }
      // File selection is an explicit action. Ask AppKit directly rather than
      // depending on the hover controller's potentially stale presentation state.
      self.popover.performClose(nil)
      return true
    },
    isPopoverVisible: { [weak self] in
      guard let self else { return false }
      return self.popover.isShown || self.isPopoverWindowVisible
    },
    onSelection: { [weak self] url in await self?.tasks.saveDashboard(url: url) },
    onFinish: { [weak self] in
      guard let self else { return }
      self.pages.showSettings(.tasks)
      // A failed handoff can leave the original popover visible. Do not begin
      // another Opening cycle: an already-shown popover may not send didShow.
      guard !self.popover.isShown && !self.isPopoverWindowVisible else { return }
      self.hoverController.reset()
      self.showPopover(settings: .tasks)
    }
  )

  private var isPopoverWindowVisible: Bool {
    popover.contentViewController?.view.window?.isVisible == true
  }
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
    NSApp.mainMenu = PulseApplicationMenu.makeMainMenu()
    NSApp.setActivationPolicy(.accessory)
    configureStatusItem()
    configurePopover()

    motionPreferencesSubscription = NSWorkspace.shared.notificationCenter
      .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updatePopoverMotion() }

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
    hoverController.reset()
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
    // Native motion is safe with HomeView's opaque adaptive background.
    updatePopoverMotion()
    popover.contentSize = HomeView.popoverSize
    let hostingController = NSHostingController(
      rootView: HomeView(
        config: config,
        usage: usage,
        vipUsage: vipUsage,
        vipConfiguration: vipConfiguration,
        tasks: tasks,
        localTasks: localTasks,
        taskSource: taskSource,
        dashboardPicker: dashboardPicker,
        pages: pages,
        onVIPCredentialsChanged: { [weak self] in self?.vipUsage.requestRefresh() },
        onSelectDashboardFile: { [weak self] in self?.dashboardPicker.requestSelection() },
        onOpenDashboardFile: { [weak self] task in self?.openDashboardFileInObsidian(task) ?? false
        },
        onQuit: { NSApp.terminate(nil) },
        onTaskEditingChanged: { [weak self] active in
          guard let self else { return }
          self.taskEditorActive = active
          self.hoverController.setDismissalSuspended(active)
        }
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
    if dashboardPicker.isSelecting {
      dashboardPicker.requestSelection()
      return
    }
    guard hoverController.state != .closing else { return }
    if popover.isShown {
      hoverController.requestClose()
    } else {
      showPopover()
    }
  }

  private func showPopover(settings: SettingsDestination? = nil) {
    guard let button = statusItem.button, hoverController.state != .closing else { return }
    config.refreshLoginItemStatus()
    vipUsage.refreshIfStale(maxAge: 60)
    if taskSource.source == .apex { tasks.requestRefresh() }
    Task { [weak self] in await self?.localTasks.refresh() }
    if let settings { pages.showSettings(settings) } else { pages.reset() }
    hoverController.beginOpening()
    hoverController.setDismissalSuspended(taskEditorActive)
    updatePopoverMotion()
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    guard popover.isShown else {
      hoverController.reset()
      return
    }
    let presence = pointerPresence()
    hoverController.synchronize(
      statusButton: presence.statusButton, content: presence.content,
      popoverWindow: presence.popoverWindow)
  }

  private func updatePopoverMotion() {
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  func popoverDidShow(_ notification: Notification) {
    hoverController.presentationDidShow()
  }

  func popoverShouldClose(_ popover: NSPopover) -> Bool {
    updatePopoverMotion()
    return true
  }

  func popoverWillClose(_ notification: Notification) {
    hoverController.beginClosing()
  }

  func popoverDidClose(_ notification: Notification) {
    hoverController.reset()
    pages.reset()
    dashboardPicker.popoverDidClose()
  }

  private func openDashboardFileInObsidian(_ task: DashboardTask) -> Bool {
    guard let url = ObsidianURLOpener.url(for: task.sourceFileURL) else { return false }
    return NSWorkspace.shared.open(url)
  }
}
