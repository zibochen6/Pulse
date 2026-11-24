import AppKit
import QuartzCore
import SwiftUI
import XCTest

@testable import Pulse

/// Opt-in artifact export using the product's native views and controllers.
/// Run scripts/export-ui-demo.sh. Fixtures cannot read real tasks, Keychain or
/// network services. Scripted model actions are not a mouse/IME acceptance test.
@MainActor
final class UIDemoExportTests: XCTestCase {
  func testExportNativeScreenshotsAndMotionFrames() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let outputPath = environment["PULSE_UI_DEMO_OUTPUT"] else {
      throw XCTSkip("Opt-in native demo export; run scripts/export-ui-demo.sh")
    }
    let language = environment["PULSE_UI_DEMO_LANGUAGE"] ?? "en"
    let output = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let fixture = try await DemoFixture(language: language)
    defer { fixture.cleanUp() }
    let dashboardStillsOnly = environment["PULSE_UI_DASHBOARD_STILLS_ONLY"] == "1"

    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      fixture.pages.showHome()
      try await exportStill(
        fixture.home, size: HomeView.popoverSize, fixture: fixture, appearance: appearance,
        destination: output.appendingPathComponent("home-\(language)-\(name).png"))
      try await exportStill(
        fixture.settings.environment(\.pulsePopoverFocus, fixture.popoverFocus),
        size: SettingsWindowController.contentSize, fixture: fixture,
        appearance: appearance,
        destination: output.appendingPathComponent("settings-\(language)-\(name).png"))
      if dashboardStillsOnly {
        for page in ProviderID.allCases {
          fixture.pages.showUsage(page)
          try await exportStill(
            fixture.home, size: HomeView.popoverSize, fixture: fixture, appearance: appearance,
            destination: output.appendingPathComponent(
              "usage-\(page.rawValue)-\(language)-\(name).png"))
        }
        fixture.pages.showTagManagement()
        try await exportStill(
          fixture.home, size: HomeView.popoverSize, fixture: fixture, appearance: appearance,
          destination: output.appendingPathComponent("tags-\(language)-\(name).png"))
        fixture.pages.showClipTask()
        try await exportStill(
          fixture.home, size: HomeView.popoverSize, fixture: fixture, appearance: appearance,
          destination: output.appendingPathComponent("clips-\(language)-\(name).png"))
        for phase in [ClipPhase.completed, .failed] {
          let preview = try fixture.recordingResult(phase)
          try await exportStill(
            fixture.home(recording: preview), size: HomeView.popoverSize, fixture: fixture,
            appearance: appearance,
            destination: output.appendingPathComponent(
              "clips-\(phase.rawValue)-\(language)-\(name).png"))
        }
      }
    }
    if dashboardStillsOnly { return }

    let frames = output.appendingPathComponent("frames-\(language)", isDirectory: true)
    try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
    let stage = DemoStage(fixture: fixture)
      .environment(\.locale, Locale(identifier: language))
    let host = NSHostingView(rootView: stage)
    let window = makeWindow(host: host, size: NSSize(width: 1024, height: 720), appearance: .aqua)
    defer { window.close() }
    try await Task.sleep(for: .milliseconds(200))
    let start = ProcessInfo.processInfo.systemUptime
    for frame in 0..<540 {
      let target = start + Double(frame) / 30
      let delay = target - ProcessInfo.processInfo.systemUptime
      if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
      try await fixture.perform(frame: frame)
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      try autoreleasepool {
        try capture(host, scale: 1).write(
          to: frames.appendingPathComponent(String(format: "%04d.png", frame)))
      }
    }
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: frames.appendingPathComponent("0539.png").path))
  }

  /// A bounded, isolated native window for human/CUA acceptance. It never
  /// synthesizes input. Remove the named sentinel to finish before the timeout.
  func testInteractiveNativePreview() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["PULSE_UI_LIVE_PREVIEW"] == "1" else {
      throw XCTSkip("Opt-in interactive preview")
    }
    let language = environment["PULSE_UI_DEMO_LANGUAGE"] ?? "en"
    let fixture = try await DemoFixture(language: language)
    let sentinel = URL(
      fileURLWithPath: environment["PULSE_UI_PREVIEW_SENTINEL"] ?? "/tmp/PulseUIDemo-preview.keep")
    try Data("Remove this file to finish the isolated Pulse preview.\n".utf8).write(to: sentinel)
    let settings = SettingsWindowController(
      rootView: fixture.settings.environment(\.locale, Locale(identifier: language)))
    fixture.interactiveSettings = settings
    let root = VStack(spacing: 0) {
      fixture.home
      Text(fixture.sampleLabel).font(.system(size: 11)).foregroundStyle(.secondary)
        .frame(width: 400, height: 28).background(PulseDesignTokens.background)
    }
    .environment(\.locale, Locale(identifier: language))
    let host = NSHostingView(rootView: root)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 548),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = "Pulse — Isolated Preview"
    fixture.interactiveHome = window
    window.contentView = host
    window.center()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    defer {
      window.close()
      settings.close()
      fixture.cleanUp()
      try? FileManager.default.removeItem(at: sentinel)
    }
    let deadline = Date().addingTimeInterval(600)
    while Date() < deadline, FileManager.default.fileExists(atPath: sentinel.path) {
      try await Task.sleep(for: .milliseconds(500))
    }
  }

  private func exportStill<V: View>(
    _ content: V, size: NSSize, fixture: DemoFixture, appearance: NSAppearance.Name,
    destination: URL
  ) async throws {
    let root = VStack(spacing: 0) {
      content
      Text(fixture.sampleLabel)
        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        .frame(width: size.width, height: 28)
        .background(PulseDesignTokens.background)
    }
    .environment(\.locale, Locale(identifier: fixture.language))
    let host = NSHostingView(rootView: root)
    let window = makeWindow(
      host: host, size: NSSize(width: size.width, height: size.height + 28), appearance: appearance)
    defer { window.close() }
    try await Task.sleep(for: .milliseconds(250))
    for _ in 0..<100 {
      if !fixture.tasks.isLoading && !fixture.tasks.isSaving { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertFalse(fixture.tasks.isLoading)
    XCTAssertFalse(fixture.tasks.isSaving)
    XCTAssertEqual(fixture.tasks.document?.tags.count, 6)
    XCTAssertEqual(fixture.tasks.document?.tasks.count, 6)
    host.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    try capture(host, scale: 2).write(to: destination)
  }

  private func makeWindow<V: View>(
    host: NSHostingView<V>, size: NSSize, appearance: NSAppearance.Name
  ) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: appearance)
    window.ignoresMouseEvents = true
    window.contentView = host
    host.frame = NSRect(origin: .zero, size: size)
    // A real hosting window supplies native field/layout/animation lifecycle,
    // but stays off the user's visible desktop and cannot receive input.
    window.setFrameOrigin(NSPoint(x: -16_000, y: -16_000))
    window.orderFront(nil)
    return window
  }

  private func capture(_ view: NSView, scale: Int) throws -> Data {
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width) * scale,
        pixelsHigh: Int(view.bounds.height) * scale, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
  }
}

@MainActor
private final class DemoFixture: ObservableObject {
  let language: String
  let suite: String
  let directory: URL
  let config: AppConfig
  let usage: UsageController
  let vipUsage: UsageController
  let deepSeekUsage: UsageController
  let antigravityUsage: UsageController
  let vipConfiguration: VIPConfiguration
  let deepSeekConfiguration: DeepSeekConfiguration
  let tasks: LocalTaskController
  let updates: UpdateController
  let clips: ClipController
  let pages = PopoverPageController()
  let popoverFocus = PulsePopoverFocus()
  let taskPresentation = LocalTaskPresentation()
  let settingsPresentation = SettingsPresentation(destination: .providers)
  let work = demoTagID(1)
  let launch = demoTagID(2)
  @Published var showsSettings = false
  @Published var caption = ""
  private var addedTaskID: UUID?
  var interactiveSettings: SettingsWindowController?
  weak var interactiveHome: NSWindow?

  var isChinese: Bool { language == "zh-Hans" }
  var sampleLabel: String {
    isChinese ? "演示数据 · 本地示例账户与任务" : "Demo data · Local sample accounts and tasks"
  }

  init(language: String) async throws {
    self.language = language
    suite = "Pulse.UIDemo.\(UUID().uuidString)"
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseUIDemo-\(UUID())")
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    config = AppConfig(defaults: defaults, loginItemService: DemoLoginItems())
    usage = UsageController(provider: DemoProvider(id: "codex"))
    vipUsage = UsageController(provider: DemoProvider(id: VIPProvider.providerID))
    deepSeekUsage = UsageController(provider: DemoProvider(id: DeepSeekProvider.providerID))
    antigravityUsage = UsageController(provider: DemoProvider(id: "antigravity"))
    vipConfiguration = VIPConfiguration(secretStore: DemoSecrets())
    deepSeekConfiguration = DeepSeekConfiguration(secretStore: DemoSecrets())
    tasks = LocalTaskController(
      store: LocalTaskStore(fileURL: directory.appendingPathComponent("tasks.json")))
    updates = makeInactiveUpdateController(defaults: defaults, currentVersion: .current())
    clips = ClipController(
      defaults: defaults, support: directory.appendingPathComponent("Clips"),
      downloads: directory.appendingPathComponent("Downloads"), live: false)
    vipConfiguration.refresh()
    deepSeekConfiguration.refresh()
    await usage.refresh()
    await vipUsage.refresh()
    await deepSeekUsage.refresh()
    await antigravityUsage.refresh()
    await tasks.refresh()
    let chinese = language == "zh-Hans"
    for (id, name) in [
      (work, chinese ? "工作" : "Work"), (launch, chinese ? "发布" : "Launch"),
      (demoTagID(3), chinese ? "灵感" : "Ideas"), (demoTagID(4), chinese ? "生活" : "Life"),
      (demoTagID(5), chinese ? "阅读" : "Reading"), (demoTagID(6), chinese ? "以后" : "Someday"),
    ] {
      let saved = await tasks.createTag(id: id, name: name)
      XCTAssertTrue(saved)
    }
    let titles =
      chinese
      ? ["为今天留一点清晰", "打磨发布页面的视觉", "写下第一篇产品更新", "给重要的事留出空间"]
      : [
        "Find a little clarity today", "Polish the launch visuals", "Write the first release note",
        "Make space for what matters",
      ]
    for title in titles {
      let saved = await tasks.saveTask(id: nil, text: title, tagIDs: [work], newTagNames: [])
      XCTAssertTrue(saved)
    }
    for title
      in (chinese
      ? ["准备中英文演示", "邀请第一批体验者"] : ["Prepare the bilingual demo", "Invite the first testers"])
    {
      let saved = await tasks.saveTask(id: nil, text: title, tagIDs: [launch], newTagNames: [])
      XCTAssertTrue(saved)
    }
    if let task = tasks.tasks(matching: .tag(work)).last {
      await tasks.setCompleted(true, taskID: task.id)?.value
    }
    taskPresentation.selectedFilter = .tag(work)
    caption = chinese ? "AI 状态与日常待办，轻松在一起。" : "AI status and everyday tasks, quietly together."
  }

  var home: some View { home(recording: clips) }

  func home(
    recording: ClipController, todayBridge: TodayTaskBridge? = nil,
    onSize: ((NSSize) -> Void)? = nil
  ) -> some View {
    HomeView(
      config: config, usage: usage, vipUsage: vipUsage, deepSeekUsage: deepSeekUsage,
      deepSeekConfiguration: deepSeekConfiguration, vipConfiguration: vipConfiguration,
      localTasks: tasks, updates: updates, pages: pages,
      onDeepSeekCredentialsChanged: { [weak self] in self?.deepSeekUsage.credentialsDidChange() },
      onVIPCredentialsChanged: { [weak self] in self?.vipUsage.credentialsDidChange() }, onQuit: {},
      localPresentation: taskPresentation,
      onOpenSettings: { [weak self] destination, provider in
        guard let self else { return }
        self.settingsPresentation.open(destination, provider: provider)
        self.showsSettings = true
        self.interactiveSettings?.open()
      }, clips: recording, antigravityUsage: antigravityUsage,
      todayBridge: todayBridge,
      onPopoverLayoutChanged: onSize.map { callback in { callback($0.size) } }
    )
    .environment(\.pulsePopoverFocus, popoverFocus)
  }

  func recordingResult(_ phase: ClipPhase) throws -> ClipController {
    let support = directory.appendingPathComponent("ClipPreview")
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    var result = ClipSnapshot(
      phase: phase, source: "rec_1042.MP4", model: "gpt-6.2-sol", effort: "low")
    if phase == .completed {
      let review = support.appendingPathComponent("review.html")
      try Data("<title>Demo review</title>".utf8).write(to: review)
      result.folder = support.path
      result.review = review.path
      result.platforms = ["Douyin", "Xiaohongshu", "Kuaishou", "Bilibili"].map {
        ClipDraft(platform: $0, status: "saved_verified", detail: "")
      }
    } else {
      result.detail = "The editing worker stopped. Open its files before retrying."
    }
    try JSONEncoder().encode(result).write(to: support.appendingPathComponent("latest.json"))
    let controller = ClipController(
      defaults: defaults, support: support, downloads: directory, live: true,
      tools: { throw CocoaError(.featureUnsupported) })
    // Restore a terminal fixture. The offscreen still never launches a worker,
    // opens a file, requests notifications or connects to a live service.
    controller.restore()
    XCTAssertEqual(controller.snapshot.phase, phase)
    return controller
  }

  var settings: some View {
    SettingsView(
      config: config, deepSeekConfiguration: deepSeekConfiguration,
      vipConfiguration: vipConfiguration, localTasks: tasks, updates: updates,
      onDeepSeekCredentialsChanged: { [weak self] in self?.deepSeekUsage.credentialsDidChange() },
      onVIPCredentialsChanged: { [weak self] in self?.vipUsage.credentialsDidChange() }, onQuit: {},
      usage: usage, vipUsage: vipUsage, deepSeekUsage: deepSeekUsage,
      antigravityUsage: antigravityUsage,
      presentation: settingsPresentation, localPresentation: taskPresentation,
      onReturnToDraft: { [weak self] in
        self?.pages.showHome()
        self?.interactiveSettings?.close()
        self?.interactiveHome?.makeKeyAndOrderFront(nil)
      }, clips: clips)
  }

  func perform(frame: Int) async throws {
    switch frame {
    case 60:
      taskPresentation.beginAddingTask()
      caption = isChinese ? "随手记下，继续专注。" : "Capture a thought. Keep your flow."
    case 80:
      taskPresentation.quickDraft.text =
        isChinese ? "录制一段轻盈的产品演示" : "Record a delightful product demo"
    case 115:
      let submission = try XCTUnwrap(taskPresentation.captureSubmission())
      addedTaskID = submission.draft.creationID
      let saved = await tasks.saveTask(
        id: nil, text: submission.draft.text, tagIDs: submission.draft.tagIDs, newTagNames: [],
        creationID: submission.draft.creationID)
      taskPresentation.finishSubmission(
        submission, saved: saved, task: tasks.document?.tasks.first { $0.id == addedTaskID },
        tags: tasks.document?.tags ?? [])
    case 155:
      if let addedTaskID { await tasks.setCompleted(true, taskID: addedTaskID)?.value }
      caption = isChinese ? "完成一件，心里更轻一点。" : "One less thing on your mind."
    case 205:
      taskPresentation.selectedFilter = .tag(launch)
      caption = isChinese ? "每个想法，都有自己的位置。" : "A clear place for every thought."
    case 245: pages.showTagManagement()
    case 280: taskPresentation.tagSearch = isChinese ? "发布" : "Launch"
    case 320:
      taskPresentation.tagSearch = ""
      pages.showHome()
    case 355:
      pages.showUsage(.deepSeek)
      caption = isChinese ? "真实的余额，清楚的状态。" : "Real balances. Clear status."
    case 410:
      showsSettings = true
      caption = isChinese ? "连接、偏好，一目了然。" : "Connections and preferences, beautifully clear."
    case 485: settingsPresentation.destination = .general
    default: break
    }
  }

  func cleanUp() {
    UserDefaults.standard.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
}

private struct DemoStage: View {
  @ObservedObject var fixture: DemoFixture

  var body: some View {
    VStack(spacing: 16) {
      HStack {
        Text("Pulse").font(.system(size: 22, weight: .semibold))
        Spacer()
        Text(fixture.sampleLabel).font(.system(size: 12)).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 40).padding(.top, 24)
      Text(fixture.caption).font(.system(size: 20, weight: .medium))
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
      Group {
        if fixture.showsSettings { fixture.settings } else { fixture.home }
      }
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
      Spacer(minLength: 0)
    }
    .frame(width: 1024, height: 720)
    .background(PulseDesignTokens.background)
  }
}

private struct DemoProvider: UsageProviding {
  let id: String
  func fetch() async throws -> UsageSnapshot {
    let metrics: [UsageMetric]
    switch id {
    case "codex", "antigravity":
      metrics = [
        .quota(
          QuotaWindow(
            durationMinutes: 300, remainingPercent: 86, resetsAt: Date().addingTimeInterval(7200)))
      ]
    case VIPProvider.providerID:
      metrics = [.balance(amount: (Decimal(425) / 10), currency: "USD")]
    default: metrics = [.balance(amount: (Decimal(1286) / 10), currency: "CNY")]
    }
    return UsageSnapshot(providerID: id, fetchedAt: Date(), metrics: metrics)
  }
}

private final class DemoSecrets: SecretStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String] = [:]
  private var removed = Set<String>()

  func read(account: String) throws -> String? {
    lock.lock()
    defer { lock.unlock() }
    return removed.contains(account) ? nil : values[account] ?? "fictional-demo-value-never-sent"
  }
  func save(_ secret: String, account: String) throws {
    lock.lock()
    defer { lock.unlock() }
    removed.remove(account)
    values[account] = secret
  }
  func delete(account: String) throws {
    lock.lock()
    defer { lock.unlock() }
    removed.insert(account)
    values[account] = nil
  }
}

@MainActor
private final class DemoLoginItems: LoginItemManaging {
  var status: LoginItemStatus { .notRegistered }
  func setEnabled(_ enabled: Bool) throws {}
}

private func demoTagID(_ index: UInt8) -> UUID {
  UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, index))
}

extension UIDemoExportTests {
  /// Uses visible native surfaces so an external Instruments recording gets
  /// real compositor samples. No global mouse events or desktop preferences.
  func testProfileVisibleMotion() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let session = environment["PULSE_MOTION_PROFILE"] else {
      throw XCTSkip("Opt-in visible motion profiling")
    }
    guard #available(macOS 14, *) else {
      throw XCTSkip("Visible profiling uses the window's display link")
    }
    try await profileMotion(in: URL(fileURLWithPath: session, isDirectory: true), environment)
  }

  @available(macOS 14, *)
  private func profileMotion(in sessionURL: URL, _ environment: [String: String]) async throws {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    try XCTSkipIf(
      session?[kCGSessionOnConsoleKey as String] as? Bool != true
        || session?["CGSSessionScreenIsLocked"] as? Bool == true,
      "Visible motion profiling needs an unlocked WindowServer session")
    let screenIndex = Int(environment["PULSE_MOTION_SCREEN"] ?? "0") ?? 0
    let screen = try XCTUnwrap(
      NSScreen.screens.indices.contains(screenIndex) ? NSScreen.screens[screenIndex] : nil)
    let fixture = try await DemoFixture(language: environment["PULSE_UI_DEMO_LANGUAGE"] ?? "en")
    defer { fixture.cleanUp() }
    let frame = screen.visibleFrame
    let anchorWindow = NSWindow(
      contentRect: NSRect(x: frame.midX - 20, y: frame.maxY - 65, width: 40, height: 28),
      styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
    // Init's content rect is screen-relative on secondary displays.
    anchorWindow.setFrameOrigin(NSPoint(x: frame.midX - 20, y: frame.maxY - 65))
    anchorWindow.isReleasedWhenClosed = false
    anchorWindow.level = .floating
    let anchor = NSView()
    anchorWindow.contentView = anchor
    let popover = NSPopover()
    popover.contentSize = HomeView.popoverSize
    let appearance = environment["PULSE_MOTION_DARK"] == "1" ? NSAppearance.Name.darkAqua : .aqua
    let tables = try await MotionTables(fixture: fixture)
    let host = NSHostingController(
      rootView: fixture.home(
        recording: fixture.clips, todayBridge: tables.bridge,
        onSize: { [weak popover] size in
          DispatchQueue.main.async {
            if let popover, popover.contentSize != size { popover.contentSize = size }
          }
        }
      )
      .environment(\.pulseHasNativeBackdrop, true)
      .environment(\.locale, Locale(identifier: fixture.language)))
    host.sizingOptions = []
    popover.appearance = NSAppearance(named: appearance)
    popover.contentViewController = host
    popover.contentSize = HomeView.popoverSize
    let settings = SettingsWindowController(
      config: fixture.config,
      rootView: fixture.settings.environment(\.locale, Locale(identifier: fixture.language)))
    let settingsWindow = try XCTUnwrap(settings.window)
    settingsWindow.appearance = NSAppearance(named: appearance)
    settingsWindow.setFrameOrigin(NSPoint(x: frame.midX - 360, y: frame.midY - 280))
    settingsWindow.level = .floating
    defer {
      popover.close()
      anchorWindow.orderOut(nil)
      settingsWindow.orderOut(nil)
    }
    anchorWindow.orderFrontRegardless()
    popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    try await Task.sleep(for: .milliseconds(450))
    XCTAssertTrue(popover.isShown)
    let popoverWindow = try XCTUnwrap(host.view.window)
    XCTAssertEqual(popoverWindow.screen, screen)
    popoverWindow.level = .floating
    popoverWindow.orderFrontRegardless()
    let settingsContent = try XCTUnwrap(settingsWindow.contentView)
    let ready = MotionReady(
      pid: ProcessInfo.processInfo.processIdentifier, display: screen.localizedName,
      maxRefresh: screen.maximumFramesPerSecond, scale: screen.backingScaleFactor)
    try JSONEncoder().encode(ready).write(to: sessionURL.appendingPathComponent("ready.json"))
    let go = sessionURL.appendingPathComponent("go").path
    let deadline = ContinuousClock.now.advanced(by: .seconds(90))
    while !FileManager.default.fileExists(atPath: go), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(40))
    }
    try XCTSkipUnless(FileManager.default.fileExists(atPath: go), "Profiler did not signal start")
    var intervals: [MotionInterval] = []
    let trialCount = max(1, Int(environment["PULSE_MOTION_TRIALS"] ?? "4") ?? 4)
    for trial in 0..<trialCount {
      // Trial zero warms layout, glyph and shader caches on this display.
      let list = try XCTUnwrap(
        host.view.motionDescendants(NSScrollView.self)
          .max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }))
      intervals.append(
        await MotionInterval.measure("local-scroll", trial: trial) {
          try await scroll(list, horizontally: false, distance: 1_550)
        })

      intervals.append(
        await MotionInterval.measure("typing", trial: trial) {
          fixture.taskPresentation.beginAddingTask()
          try await Task.sleep(for: .milliseconds(250))
          let field = try XCTUnwrap(
            host.view.motionDescendants(NSTextField.self).first {
              $0.accessibilityIdentifier() == "localTaskTextField"
            })
          let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
          let replacement = editor.selectedRange()
          editor.setMarkedText(
            "qing", selectedRange: NSRange(location: 4, length: 0), replacementRange: replacement)
          XCTAssertTrue(editor.hasMarkedText())
          editor.insertText("清", replacementRange: editor.markedRange())
          XCTAssertFalse(editor.hasMarkedText())
          for syllable in ["楚", "的", "反馈", " keeps ", "focus", " in ", "place"] {
            editor.insertText(syllable, replacementRange: editor.selectedRange())
            try await Task.sleep(for: .milliseconds(40))
          }
          XCTAssertTrue(fixture.taskPresentation.quickDraft.text.contains("focus"))
          fixture.taskPresentation.collapseComposer()
          try await Task.sleep(for: .milliseconds(140))
          return []
        })

      intervals.append(
        await MotionInterval.measure("completion-and-navigation", trial: trial) {
          for task in fixture.tasks.tasks(matching: .untagged).prefix(5) {
            await fixture.tasks.setCompleted(!task.completed, taskID: task.id)?.value
            try await Task.sleep(for: .milliseconds(55))
          }
          for page in [PopoverPage.usage(.codex), .tagManagement, .usage(.deepSeek), .home] {
            switch page {
            case .home: fixture.pages.showHome()
            case .tagManagement: fixture.pages.showTagManagement()
            case .usage(let provider): fixture.pages.showUsage(provider)
            case .clipTask: fixture.pages.showClipTask()
            }
            try await Task.sleep(for: .milliseconds(95))
          }
          return []
        })

      intervals.append(
        await MotionInterval.measure("tag-strip-scroll", trial: trial) {
          let tagStrip = try XCTUnwrap(
            host.view.motionDescendants(NSScrollView.self).first {
              ($0.documentView?.frame.width ?? 0) > 750
            })
          guard let tag = fixture.tasks.document?.tags.first else {
            throw CocoaError(.fileReadCorruptFile)
          }
          fixture.taskPresentation.beginTagDrag(tag.id, nativeSession: true)
          defer { fixture.taskPresentation.endTagDrag() }
          return try await scroll(tagStrip, horizontally: true, distance: 960)
        })

      intervals.append(
        await MotionInterval.measure("today-resize-and-scroll", trial: trial) {
          try await tables.connect()
          try await Task.sleep(for: .milliseconds(270))
          try await tables.publish(count: 320)
          try await Task.sleep(for: .milliseconds(275))
          let list = try XCTUnwrap(
            host.view.motionDescendants(NSScrollView.self)
              .max(by: {
                ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0)
              }))
          let frames = try await scroll(list, horizontally: false, distance: 1_550)
          try await tables.publish(count: 3)
          try await Task.sleep(for: .milliseconds(270))
          try await tables.bridge.disconnect()
          return frames
        })

      intervals.append(
        await MotionInterval.measure("settings-and-glass", trial: trial) {
          settingsWindow.orderFrontRegardless()
          fixture.settingsPresentation.open(.general, provider: nil)
          try await Task.sleep(for: .milliseconds(200))
          let intervals = try await MotionDisplayClock().drive(view: settingsContent) {
            fixture.config.setWindowTransparencyPercent(Int(50 * (1 - abs(2 * $0 - 1))))
          }
          fixture.settingsPresentation.open(.providers, provider: .codex)
          try await Task.sleep(for: .milliseconds(180))
          fixture.settingsPresentation.open(.tasks, provider: nil)
          try await Task.sleep(for: .milliseconds(180))
          settingsWindow.orderOut(nil)
          popoverWindow.orderFrontRegardless()
          try await Task.sleep(for: .milliseconds(180))
          return intervals
        })
    }
    try JSONEncoder().encode(intervals).write(
      to: sessionURL.appendingPathComponent("intervals.json"))
    let finish = sessionURL.appendingPathComponent("finish").path
    let finishDeadline = ContinuousClock.now.advanced(by: .seconds(65))
    while !FileManager.default.fileExists(atPath: finish), ContinuousClock.now < finishDeadline {
      try await Task.sleep(for: .milliseconds(100))
    }
  }

  @available(macOS 14, *)
  private func scroll(
    _ scroll: NSScrollView, horizontally: Bool, distance: CGFloat
  ) async throws -> [Double] {
    let clip = scroll.contentView
    let document = try XCTUnwrap(scroll.documentView)
    let maximum =
      horizontally
      ? document.frame.width - clip.bounds.width : document.frame.height - clip.bounds.height
    XCTAssertGreaterThan(maximum, 150)
    clip.scroll(to: .zero)
    let samples = try await MotionDisplayClock().drive(view: clip) { phase in
      let offset = min(maximum, distance) * (1 - abs(2 * phase - 1))
      let point = horizontally ? NSPoint(x: offset, y: 0) : NSPoint(x: 0, y: offset)
      clip.scroll(to: point)
      scroll.reflectScrolledClipView(clip)
    }
    XCTAssertFalse(samples.isEmpty, "Visible content must receive display callbacks")
    return samples
  }
}

private struct MotionReady: Encodable {
  let pid: Int32
  let display: String
  let maxRefresh: Int
  let scale: Double
}

private struct MotionInterval: Encodable {
  let scene: String
  let trial: Int
  let start: Double
  let end: Double
  let callbackIntervals: [Double]
  let error: String?

  @MainActor
  static func measure(
    _ scene: String, trial: Int, run: () async throws -> [Double]
  ) async -> Self {
    let start = Date().timeIntervalSince1970
    do {
      let intervals = try await run()
      let detail = "PulseMotion \(trial) \(scene): \(intervals.count) display intervals\n"
      try? FileHandle.standardError.write(contentsOf: Data(detail.utf8))
      return Self(
        scene: scene, trial: trial, start: start, end: Date().timeIntervalSince1970,
        callbackIntervals: intervals, error: nil)
    } catch {
      XCTFail("\(scene): \(error)")
      return Self(
        scene: scene, trial: trial, start: start, end: Date().timeIntervalSince1970,
        callbackIntervals: [], error: String(describing: error))
    }
  }
}

@MainActor
private struct MotionTables {
  let bridge: TodayTaskBridge
  let vault: URL
  let root: URL
  let now = Date()

  init(fixture: DemoFixture) async throws {
    vault = fixture.directory.appendingPathComponent("Motion vault", isDirectory: true)
    let plugin = vault.appendingPathComponent(".obsidian/plugins/dora-personal-dashboard")
    try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
    try Data(#"{"id":"dora-personal-dashboard","version":"0.6.10"}"#.utf8)
      .write(to: plugin.appendingPathComponent("manifest.json"))
    root = fixture.directory.appendingPathComponent("ObsidianToday/v1", isDirectory: true)
    let date = now
    bridge = TodayTaskBridge(
      defaults: try XCTUnwrap(UserDefaults(suiteName: fixture.suite)), bridgeRoot: root,
      now: { date })
    let tasks = (0..<320).map { index in
      LocalTask(text: Self.title(index), completed: index % 3 == 0, repeatsDaily: index % 8 == 0)
    }
    let tags = (1...32).map { TaskTag(id: demoTagID($0), name: "List \($0) · 示例") }
    try JSONEncoder().encode(LocalTaskDocument(tasks: tasks, tags: tags))
      .write(to: fixture.directory.appendingPathComponent("tasks.json"), options: .atomic)
    await fixture.tasks.refresh()
    fixture.taskPresentation.selectedFilter = .untagged
    XCTAssertEqual(fixture.tasks.tasks(matching: .untagged).count, 320)
  }

  func connect() async throws {
    try await bridge.connect(to: vault)
    try await publish(count: 3)
  }

  func publish(count: Int) async throws {
    let id = TodayBridgeVault(canonicalURL: try XCTUnwrap(bridge.vaultURL)).id
    let rows = (0..<count).map { index in
      TodayBridgeRecordedTask(
        id: String(format: "%064x", index + 1), title: Self.title(index),
        completed: index % 3 == 0, source: .quick)
    }
    let board = TodayBridgeBoardDocument(
      vaultID: id, heartbeat: Int64(now.timeIntervalSince1970 * 1000),
      day: TodayBridgeStorage.dayKey(for: now), tasks: rows)
    let channel = root.appendingPathComponent(id, isDirectory: true)
    try JSONEncoder().encode(board).write(
      to: channel.appendingPathComponent("board.json"), options: .atomic)
    await bridge.refresh()
    XCTAssertEqual(bridge.tasks.count, count)
  }

  private static func title(_ index: Int) -> String {
    index % 5 == 0
      ? "Task \(index) · 整理本周内容并核对进度。Read the notes and update the draft before the next check."
      : "Task \(index) · 今日事项"
  }
}

@MainActor
@available(macOS 14, *)
private final class MotionDisplayClock: NSObject {
  private var link: CADisplayLink?
  private var update: ((Double) -> Void)?
  private var continuation: CheckedContinuation<[Double]?, Never>?
  private var firstFrame: CFTimeInterval?
  private var lastFrame: CFTimeInterval?
  private var intervals: [Double] = []

  func drive(view: NSView, update: @escaping (Double) -> Void) async throws -> [Double] {
    self.update = update
    let timeout = Task { [weak self] in
      try await Task.sleep(for: .seconds(3))
      self?.finish(completed: false)
    }
    defer { timeout.cancel() }
    let samples: [Double]? = await withCheckedContinuation { continuation in
      self.continuation = continuation
      let link = view.displayLink(target: self, selector: #selector(frame(_:)))
      self.link = link
      let maximum = Float(view.window?.screen?.maximumFramesPerSecond ?? 60)
      link.preferredFrameRateRange = CAFrameRateRange(
        minimum: min(maximum, 60), maximum: maximum, preferred: maximum)
      link.add(to: .main, forMode: .common)
    }
    return try XCTUnwrap(samples, "Visible display link did not complete the sweep")
  }

  @objc private func frame(_ link: CADisplayLink) {
    let time = link.targetTimestamp
    if let lastFrame { intervals.append(time - lastFrame) }
    lastFrame = time
    if firstFrame == nil { firstFrame = time }
    let progress = min(1, (time - (firstFrame ?? time)) / 1.15)
    update?(progress)
    if progress >= 1 { finish(completed: true) }
  }

  private func finish(completed: Bool) {
    link?.invalidate()
    link = nil
    continuation?.resume(returning: completed ? intervals : nil)
    continuation = nil
  }
}

extension NSView {
  fileprivate func motionDescendants<V: NSView>(_ type: V.Type) -> [V] {
    (self as? V).map { [$0] } ?? subviews.flatMap { $0.motionDescendants(type) }
  }
}
