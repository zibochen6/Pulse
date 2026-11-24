import AppKit
import Combine
import SwiftUI

@MainActor
final class PulseAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private static let runtimeServices = PulseRuntimeServices()
  private static let antigravityRefreshSeconds: TimeInterval = 600
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

  private let config = AppConfig(
    defaults: PulseAppDelegate.runtimeDefaults,
    loginItemService: PulseAppDelegate.runtimeServices.loginItemService)
  private let usage = UsageController(
    provider: PulseAppDelegate.runtimeServices.usageProvider(CodexProvider()))
  private let deepSeekConfiguration = DeepSeekConfiguration(
    secretStore: PulseAppDelegate.runtimeServices.secretStore)
  private let deepSeekUsage = UsageController(
    provider: PulseAppDelegate.runtimeServices.usageProvider(DeepSeekProvider()),
    refreshInterval: .seconds(600))
  private let vipConfiguration = VIPConfiguration(
    secretStore: PulseAppDelegate.runtimeServices.secretStore)
  private let vipUsage = UsageController(
    provider: PulseAppDelegate.runtimeServices.usageProvider(VIPProvider()),
    refreshInterval: .seconds(600))
  private let antigravityUsage = UsageController(
    provider: PulseAppDelegate.runtimeServices.usageProvider(AntigravityProvider()),
    refreshInterval: .seconds(PulseAppDelegate.antigravityRefreshSeconds))
  private let localTasks = LocalTaskController(
    store: LocalTaskStore(
      fileURL:
        ProcessInfo.processInfo.environment["PULSE_DISABLE_LIVE_USAGE"] == "1"
        ? FileManager.default.temporaryDirectory.appendingPathComponent(
          "PulseTestHost-\(ProcessInfo.processInfo.processIdentifier)/tasks.json")
        : LocalTaskStore.defaultFileURL))
  private let localPresentation = LocalTaskPresentation()
  private let todayBridge = TodayTaskBridge(
    defaults: PulseAppDelegate.runtimeDefaults,
    bridgeRoot: PulseAppDelegate.runtimeServices.permitsLiveAccess
      ? TodayBridgeStorage.defaultRoot
      : FileManager.default.temporaryDirectory.appendingPathComponent(
        "PulseTestHost-\(ProcessInfo.processInfo.processIdentifier)/ObsidianToday/v1",
        isDirectory: true))
  private lazy var clips = ClipController.production(defaults: Self.runtimeDefaults,
    live: Self.runtimeServices.permitsLiveAccess)
  private lazy var clipNotifications = ClipNotifications()
  private let todayPresentation = TodayTaskPresentation()
  private let settingsPresentation = SettingsPresentation()
  private var settingsController: SettingsWindowController?
  private let interactionHolds = PopoverInteractionHolds()
  private var menuSubscriptions = Set<AnyCancellable>()
  private var menuLeases: [ObjectIdentifier: PopoverInteractionHolds.Lease] = [:]
  private var approvedTermination = false
  private lazy var exitCoordinator = PulseExitCoordinator(
    policy: { [unowned self] in self.exitPolicy },
    confirmDiscard: { [unowned self] action in self.confirmDiscard(for: action) },
    discard: { [unowned self] in
      self.localPresentation.discardAllDrafts()
      self.todayPresentation.discardAllDrafts()
      self.settingsPresentation.discardAllDrafts()
    },
    perform: { [unowned self] action in
      self.approvedTermination = true
      if action == .restart {
        self.updates.restartToUpdate()
        if case .installing = self.updates.phase {} else { self.approvedTermination = false }
      } else {
        NSApp.terminate(nil)
      }
    })
  private let pages = PopoverPageController()
  private lazy var focusChime = NSSound(named: "Glass")
  private lazy var focusTimer = FocusTimerController(onCompletion: { [weak self] in
    guard let self else { return }
    if self.focusChime?.play() != true { NSSound.beep() }
  })
  private var focusTimerSubscription: AnyCancellable?
  private var wakeSubscription: AnyCancellable?
  /// Updates are user-visible state, so the controller lives for the app's
  /// lifetime and is shared by the popover and Settings.
  private lazy var updates = UpdateController(
    feed: PulseAppDelegate.runtimeServices.updateFeed,
    downloader: PulseAppDelegate.runtimeServices.updateDownloader,
    installer: PulseAppDelegate.runtimeServices.updateInstaller(
      scriptDirectory: UpdateController.defaultSupportDirectory.appendingPathComponent(
        "Scripts", isDirectory: true)),
    preferences: UpdatePreferences(defaults: PulseAppDelegate.runtimeDefaults),
    // A restart while the user is editing a task would discard the draft, so
    // the controller waits for the popover to be closed instead.
    canApplyAutomatically: { [weak self] in
      guard let self else { return false }
      return self.exitPolicy.canInstallAutomatically
    }
  )
  private let popover = NSPopover()
  private var reopenIntent = PopoverReopenIntent()
  private var isPopoverPresenting = false
  private var latestPopoverLayout: HomeView.PopoverLayout?
  private var homePopoverLayout: HomeView.PopoverLayout?
  private var isPopoverResizeScheduled = false
  private let popoverFocus = PulsePopoverFocus()
  private var popoverInputMonitor: Any?
  private var credentialRefresh: Task<Void, Never>?
  private var preferencesSubscription: AnyCancellable?
  private var usageTrackingSubscriptions: [AnyCancellable] = []
  private var usageSubscription: AnyCancellable?
  private var displayAccessibilitySubscription: AnyCancellable?
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
    NSApp.mainMenu = PulseApplicationMenu.makeMainMenu(target: self)
    NSApp.setActivationPolicy(.accessory)
    vipConfiguration.refresh()
    deepSeekConfiguration.refresh()
    if Self.runtimeServices.permitsLiveAccess {
      clipNotifications.register()
      clips.requestNotifications = { [weak self] in self?.clipNotifications.requestPermission() }
      clips.onFinish = { [weak self] result in
        if result.phase != .noClip { self?.clipNotifications.deliver(result) }
        self?.updates.scheduleAutomaticInstallWhenIdle()
      }
      clips.restore()
    }
    configureStatusItem()
    configurePopover()
    observeMenuInteractions()
    todayBridge.start()

    focusTimerSubscription = focusTimer.$isRunning.dropFirst()
      .sink { [weak self] isRunning in
        if !isRunning { self?.updates.scheduleAutomaticInstallWhenIdle() }
      }
    wakeSubscription = NSWorkspace.shared.notificationCenter
      .publisher(for: NSWorkspace.didWakeNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.focusTimer.finishIfDue()
        Task { [weak self] in await self?.todayBridge.refresh() }
      }

    displayAccessibilitySubscription = NSWorkspace.shared.notificationCenter
      .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updateDisplayAccessibility() }

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
      usageTrackingSubscriptions = [
        trackUsage(config.$vipBalanceEnabled, with: vipUsage),
        trackUsage(config.$deepSeekBalanceEnabled, with: deepSeekUsage),
        trackUsage(config.$antigravityEnabled, with: antigravityUsage, resetOnStop: true),
      ]
      updates.start()
    }
  }

  private func trackUsage(
    _ enabled: Published<Bool>.Publisher, with controller: UsageController,
    resetOnStop: Bool = false
  ) -> AnyCancellable {
    enabled.sink { isEnabled in
      if isEnabled {
        controller.start()
      } else {
        controller.stop(reset: resetOnStop)
      }
    }
  }

  static func shouldStartLiveUsage(environment: [String: String]) -> Bool {
    PulseRuntimeServices(environment: environment).permitsLiveAccess
  }

  func applicationWillTerminate(_ notification: Notification) {
    reopenIntent.clear()
    hoverController.reset()
    stopTrackingPopoverInput()
    credentialRefresh?.cancel()
    focusTimerSubscription?.cancel()
    focusTimer.cancel()
    // A staged update is applied here when the user quits before restarting;
    // the installer does not relaunch in that case.
    updates.applyOnTerminate()
    usage.stop()
    vipUsage.stop()
    deepSeekUsage.stop()
    usageTrackingSubscriptions.removeAll()
    antigravityUsage.stop()
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    button.image = loadMenuBarIcon()
    button.imagePosition = .imageLeading
    button.toolTip = PulseLocalization.string("Pulse · Loading Codex usage")
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
    updateDisplayAccessibility()
    let hostingController = NSHostingController(
      rootView: HomeView(
        config: config,
        usage: usage,
        vipUsage: vipUsage,
        deepSeekUsage: deepSeekUsage,
        deepSeekConfiguration: deepSeekConfiguration,
        vipConfiguration: vipConfiguration,
        localTasks: localTasks,
        updates: updates,
        pages: pages,
        onDeepSeekCredentialsChanged: { [weak self] in self?.deepSeekUsage.credentialsDidChange() },
        onVIPCredentialsChanged: { [weak self] in self?.vipUsage.credentialsDidChange() },
        onQuit: { [weak self] in self?.requestQuit(nil) },
        onTaskEditingChanged: { [weak self] active in
          self?.interactionHolds.set(.taskEditor, active: active)
        },
        localPresentation: localPresentation,
        onOpenSettings: { [weak self] destination, provider in
          self?.showSettings(destination, provider: provider)
        },
        onRestartRequested: { [weak self] in self?.requestExit(restarting: true) },
        clips: clips, focusTimer: focusTimer,
        antigravityUsage: antigravityUsage,
        todayBridge: todayBridge, todayPresentation: todayPresentation,
        onPopoverLayoutChanged: { [weak self] layout in self?.reportPopoverLayout(layout) }
      )
      .environment(\.pulsePopoverFocus, popoverFocus)
      .environment(\.pulseHasNativeBackdrop, true)
    )
    // AppKit has one explicit size target. SwiftUI lays out in that viewport.
    hostingController.sizingOptions = []
    popover.contentViewController = hostingController
    popover.contentSize = HomeView.popoverSize
    installTrackingArea(on: hostingController.view, owner: contentTrackingOwner)
  }

  private func reportPopoverLayout(_ layout: HomeView.PopoverLayout) {
    latestPopoverLayout = layout
    if layout.page == .home { homePopoverLayout = layout }
    schedulePopoverResize()
  }

  private var canResizePopover: Bool {
    popover.isShown && !isPopoverPresenting && hoverController.state != .closing
  }

  private func schedulePopoverResize() {
    guard canResizePopover, !isPopoverResizeScheduled else { return }
    isPopoverResizeScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isPopoverResizeScheduled = false
      guard self.canResizePopover, let layout = self.latestPopoverLayout,
        self.matchesCurrentLayout(layout)
      else { return }
      self.setPopoverSize(layout.size)
    }
  }

  private func matchesCurrentLayout(_ layout: HomeView.PopoverLayout) -> Bool {
    layout.page == pages.page && layout.vault == todayBridge.vaultURL
      && layout.stagedVersion == updates.stagedRelease?.version
  }

  private func setPopoverSize(_ size: NSSize) {
    if popover.contentSize != size { popover.contentSize = size }
  }

  private var exitPolicy: PulseExitPolicy {
    PulseExitPolicy(
      popoverOpen: popover.isShown || reopenIntent.isScheduled,
      settingsOpen: settingsController?.isOpen == true,
      hasUnsavedEdits: localPresentation.hasUnsavedEdits || todayPresentation.hasUnsavedEdits
        || settingsPresentation.hasUnsavedEdits,
      hasPendingWrites: localTasks.isSaving || localTasks.isUndoing
        || localPresentation.hasPendingSubmissions || todayPresentation.hasPendingSubmission
        || todayBridge.hasPendingWrite,
      focusSessionActive: focusTimer.isRunning, clipJobActive: clips.snapshot.phase.isActive)
  }

  @objc func openSettings(_ sender: Any?) { showSettings() }

  private func showSettings(_ destination: SettingsDestination? = nil, provider: ProviderID? = nil)
  {
    reopenIntent.clear()
    settingsPresentation.open(destination, provider: provider)
    if settingsController == nil {
      settingsController = SettingsWindowController(
        config: config,
        rootView: SettingsView(
          config: config, deepSeekConfiguration: deepSeekConfiguration,
          vipConfiguration: vipConfiguration, localTasks: localTasks, updates: updates,
          onDeepSeekCredentialsChanged: { [weak self] in self?.deepSeekUsage.credentialsDidChange()
          },
          onVIPCredentialsChanged: { [weak self] in self?.vipUsage.credentialsDidChange() },
          onQuit: { [weak self] in self?.requestQuit(nil) },
          usage: usage, vipUsage: vipUsage, deepSeekUsage: deepSeekUsage,
          antigravityUsage: antigravityUsage,
          presentation: settingsPresentation, localPresentation: localPresentation,
          onRestartRequested: { [weak self] in self?.requestExit(restarting: true) },
          onReturnToDraft: { [weak self] in
            guard let self else { return }
            self.settingsController?.close()
            self.pages.showHome()
            self.showPopover(from: PopoverReopenIntent.Source(event: NSApp.currentEvent))
          },
          clips: clips, todayBridge: todayBridge
        ))
    }
    // Establish activity before closing the popover: the updater cannot see a
    // quiet gap between the two native surfaces.
    settingsController?.prepareToOpen()
    if popover.isShown { hoverController.requestClose() }
    settingsController?.open()
  }

  private func observeMenuInteractions() {
    interactionHolds.onChange = { [weak self] active in
      self?.hoverController.setDismissalSuspended(active)
    }
    NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
      .sink { [weak self] notification in
        guard let self, self.popover.isShown, let menu = notification.object as? NSMenu else {
          return
        }
        let id = ObjectIdentifier(menu)
        if self.menuLeases[id] == nil {
          self.menuLeases[id] = self.interactionHolds.begin(.menu(id))
        }
      }.store(in: &menuSubscriptions)
    NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
      .sink { [weak self] notification in
        guard let self, let menu = notification.object as? NSMenu,
          let lease = self.menuLeases.removeValue(forKey: ObjectIdentifier(menu))
        else { return }
        self.interactionHolds.end(lease)
      }.store(in: &menuSubscriptions)
  }

  @objc func requestQuit(_ sender: Any?) { requestExit(restarting: false) }

  private func requestExit(restarting: Bool) {
    reopenIntent.clear()
    Task { [weak self] in
      await self?.exitCoordinator.request(restarting ? .restart : .quit)
    }
  }

  private func confirmDiscard(for action: PulseExitCoordinator.Action) -> Bool {
    let alert = NSAlert()
    alert.messageText = PulseLocalization.string(
      action == .restart ? "Restart with unsaved changes?" : "Quit with unsaved changes?")
    alert.informativeText = PulseLocalization.string(
      "You have unfinished input in Pulse. Continue editing to keep it, or discard it before leaving."
    )
    alert.addButton(withTitle: PulseLocalization.string("Continue editing"))
    alert.addButton(
      withTitle: PulseLocalization.string(
        action == .restart ? "Discard and restart" : "Discard and quit"))
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal() == .alertSecondButtonReturn
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if approvedTermination { return .terminateNow }
    if !exitPolicy.hasUnsavedEdits && !exitPolicy.hasPendingWrites { return .terminateNow }
    requestExit(restarting: false)
    return .terminateCancel
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
    let pointer = NSEvent.mouseLocation
    let overPanel = contentView?.window.map {
      PopoverPointerPresence.coversPopover(pointer, frame: $0.frame, screen: $0.screen?.frame)
    } ?? false
    return PopoverPointerPresence(
      statusButton: pointerInside(statusItem.button, at: pointer),
      content: pointerInside(contentView, at: pointer),
      popoverWindow: overPanel
    )
  }

  private func pointerInside(_ view: NSView?, at pointer: NSPoint) -> Bool {
    guard let view, let window = view.window else { return false }
    let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
    return rect.contains(pointer)
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
      button.toolTip = PulseLocalization.string("Codex usage is loading")
    case .success(let snapshot):
      button.toolTip =
        PulseLocalization.format(
          "Codex usage · updated %@",
          DateFormatter.localizedString(
            from: snapshot.fetchedAt, dateStyle: .none, timeStyle: .short))
    case .unavailable(let message), .failure(let message):
      button.toolTip = message
    }
  }

  @objc private func togglePopover() {
    let source = PopoverReopenIntent.Source(event: NSApp.currentEvent)
    if hoverController.state == .closing || reopenIntent.isScheduled {
      reopenIntent.toggle(from: source)
    } else if popover.isShown {
      hoverController.requestClose()
    } else {
      showPopover(from: source)
    }
  }

  private func showPopover(from source: PopoverReopenIntent.Source) {
    if hoverController.state == .closing || reopenIntent.isScheduled {
      reopenIntent.request(from: source)
      return
    }
    guard !popover.isShown, let button = statusItem.button, button.window != nil else { return }
    let viaKeyboard = source == .keyboard
    popoverFocus.setKeyboardNavigation(viaKeyboard)
    pages.reset()

    if let layout = homePopoverLayout, matchesCurrentLayout(layout) {
      setPopoverSize(layout.size)
    } else {
      setPopoverSize(HomeView.popoverSize)
    }
    hoverController.beginOpening()
    let taskEditorActive: Bool
    if let vault = todayBridge.vaultURL {
      taskEditorActive = todayPresentation.isEditing(in: vault)
    } else {
      taskEditorActive = localPresentation.isInteractionActive
    }
    interactionHolds.set(.taskEditor, active: taskEditorActive)
    hoverController.setDismissalSuspended(interactionHolds.isActive)
    updateDisplayAccessibility()
    isPopoverPresenting = true
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    guard popover.isShown else {
      isPopoverPresenting = false
      hoverController.reset()
      return
    }
    if !viaKeyboard, let window = popover.contentViewController?.view.window,
      !(window.firstResponder is NSTextView)
    {
      window.makeFirstResponder(nil)
    }
    trackPopoverInput()
    let presence = pointerPresence()
    hoverController.synchronize(
      statusButton: presence.statusButton, content: presence.content,
      popoverWindow: presence.popoverWindow)
    refreshPopoverData()
  }

  private func refreshPopoverData() {
    if credentialRefresh == nil {
      credentialRefresh = Task { [weak self] in
        guard let self else { return }
        async let vip: Void = self.vipConfiguration.refreshInBackground()
        async let deepSeek: Void = self.deepSeekConfiguration.refreshInBackground()
        _ = await (vip, deepSeek)
        self.credentialRefresh = nil
      }
    }
    if config.vipBalanceEnabled { vipUsage.refreshIfStale(maxAge: 60) }
    if config.deepSeekBalanceEnabled { deepSeekUsage.refreshIfStale(maxAge: 60) }
    if config.antigravityEnabled, case .success = antigravityUsage.state {
      antigravityUsage.refreshIfStale(maxAge: Self.antigravityRefreshSeconds)
    }
    if todayBridge.isEnabled {
      Task { [weak self] in await self?.todayBridge.refresh() }
    } else {
      Task { [weak self] in
        await self?.localTasks.refresh()
        // Re-arm local repeats when their list is opened.
        await self?.localTasks.resetRepeatingTasks()
      }
    }
  }

  private func trackPopoverInput() {
    stopTrackingPopoverInput()
    popoverInputMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      MainActor.assumeIsolated {
        guard let self, let window = self.popover.contentViewController?.view.window,
          event.window === window
        else { return }
        self.popoverFocus.handleInput(event)
      }
      return event
    }
  }

  private func stopTrackingPopoverInput() {
    if let popoverInputMonitor {
      NSEvent.removeMonitor(popoverInputMonitor)
      self.popoverInputMonitor = nil
    }
  }

  private func updateDisplayAccessibility() {
    let workspace = NSWorkspace.shared
    config.setSystemReducesTransparency(workspace.accessibilityDisplayShouldReduceTransparency)
    popover.animates = !workspace.accessibilityDisplayShouldReduceMotion
  }

  func popoverDidShow(_ notification: Notification) {
    isPopoverPresenting = false
    hoverController.presentationDidShow()
    schedulePopoverResize()
  }

  func popoverShouldClose(_ popover: NSPopover) -> Bool {
    // The status action owns clicks on its button. A transient close for that
    // same click would turn the forthcoming action into a spurious reopen.
    if hoverController.state != .closing, let event = NSApp.currentEvent,
      event.type == .leftMouseDown || event.type == .leftMouseUp,
      let button = statusItem.button, let buttonWindow = button.window,
      event.window === buttonWindow,
      button.bounds.contains(button.convert(event.locationInWindow, from: nil))
    {
      return false
    }
    updateDisplayAccessibility()
    return true
  }

  func popoverWillClose(_ notification: Notification) {
    hoverController.beginClosing()
  }

  func popoverDidClose(_ notification: Notification) {
    isPopoverPresenting = false
    stopTrackingPopoverInput()
    menuLeases.removeAll()
    interactionHolds.reset()
    hoverController.reset()
    pages.reset()

    guard reopenIntent.scheduleAfterClose() else { return }
    // Opening here would reenter AppKit's closing notification stack.
    DispatchQueue.main.async { [weak self] in
      guard let self, let source = self.reopenIntent.consumeScheduledOpen() else { return }
      self.showPopover(from: source)
    }
  }
}

/// One explicit open request can cross the native close boundary. Extra
/// status-item clicks toggle it while AppKit finishes closing.
struct PopoverReopenIntent {
  enum Source: Equatable {
    case pointer, keyboard

    init(event: NSEvent?) {
      self = event?.type == .keyDown || event?.type == .keyUp ? .keyboard : .pointer
    }
  }

  private var source: Source?
  private(set) var isScheduled = false

  mutating func toggle(from source: Source) {
    self.source = self.source == nil ? source : nil
  }

  mutating func request(from source: Source) {
    self.source = source
  }

  mutating func clear() { source = nil }

  mutating func scheduleAfterClose() -> Bool {
    guard source != nil, !isScheduled else { return false }
    isScheduled = true
    return true
  }

  mutating func consumeScheduledOpen() -> Source? {
    guard isScheduled else { return nil }
    isScheduled = false
    defer { source = nil }
    return source
  }
}
