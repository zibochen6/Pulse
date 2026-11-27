import AppKit
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class DeepSeekRenderingTests: XCTestCase {
  func testBusyGlyphPreservesItsIdleMarkUntilTheDelayAndRestoresItAfterCompletion() throws {
    let now = ContinuousClock.Instant.now

    func renderMark(isBusy: Bool, startedAt: ContinuousClock.Instant?) throws -> NSBitmapImageRep {
      let renderer = ImageRenderer(
        content: PulseBusyGlyph(isBusy: isBusy, startedAt: startedAt) {
          Rectangle().fill(Color.red).frame(width: 18, height: 18)
        }
        .frame(width: 24, height: 24)
        .foregroundStyle(Color.black)
        .background(Color.white)
        .environment(\.pulseReduceMotionOverride, true))
      renderer.scale = 2
      let data = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
      return try XCTUnwrap(NSBitmapImageRep(data: data))
    }

    let waiting = try renderMark(isBusy: true, startedAt: now.advanced(by: .seconds(30)))
    let ongoing = try renderMark(isBusy: true, startedAt: now.advanced(by: .seconds(-1)))
    let finished = try renderMark(isBusy: false, startedAt: now.advanced(by: .seconds(-1)))
    XCTAssertEqual(waiting.size, ongoing.size)
    XCTAssertEqual(ongoing.size, finished.size)

    func redDominance(_ bitmap: NSBitmapImageRep) throws -> CGFloat {
      let color = try XCTUnwrap(
        bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
          .usingColorSpace(.deviceRGB))
      return color.redComponent - color.greenComponent
    }
    XCTAssertGreaterThan(try redDominance(waiting), 0.5)
    XCTAssertLessThan(try redDominance(ongoing), 0.05)
    XCTAssertGreaterThan(try redDominance(finished), 0.5)
    let showsStaticMark = (0..<ongoing.pixelsHigh).contains { y in
      (0..<ongoing.pixelsWide).contains { x in
        guard let pixel = ongoing.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
          return false
        }
        return pixel.alphaComponent > 0.8 && pixel.brightnessComponent < 0.5
      }
    }
    XCTAssertTrue(showsStaticMark, "Reduce Motion still presents a visible busy indicator")
  }

  func testBalanceVisibilityPersistsForEachServiceIndependently() throws {
    let suite = "PulseBalanceVisibility.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let config = AppConfig(defaults: defaults, loginItemService: RenderLoginItems())
    XCTAssertEqual(config.enabledUsageProviders, [.codex, .vip, .deepSeek])

    config.setAntigravityEnabled(true)
    for (showVIP, showDeepSeek) in [(false, true), (true, false), (false, false), (true, true)] {
      config.setVIPBalanceEnabled(showVIP)
      config.setDeepSeekBalanceEnabled(showDeepSeek)
      let restored = AppConfig(defaults: defaults, loginItemService: RenderLoginItems())
      XCTAssertEqual(restored.enabledUsageProviders.contains(.vip), showVIP)
      XCTAssertEqual(restored.enabledUsageProviders.contains(.deepSeek), showDeepSeek)
      XCTAssertTrue(restored.enabledUsageProviders.contains(.codex))
      XCTAssertTrue(restored.enabledUsageProviders.contains(.antigravity))
    }
  }

  func testAntigravityIconRendersColoredPixelsAtHomeSize() throws {
    let renderer = ImageRenderer(content: AntigravityProviderIcon(size: 16))
    renderer.scale = 2
    let image = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: image))
    let colored = (0..<bitmap.pixelsHigh).reduce(0) { count, y in
      count
        + (0..<bitmap.pixelsWide).filter { x in
          guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            return false
          }
          let channels = [color.redComponent, color.greenComponent, color.blueComponent]
          let spread = (channels.max() ?? 0) - (channels.min() ?? 0)
          return color.alphaComponent > 0.8 && spread > 0.25
        }.count
    }
    XCTAssertGreaterThan(colored, 45, "A white tile or monochrome fallback is insufficient")
  }

  func testTaskRegionStartsUnderToolbarAndAboveAIInBothAppearances() async throws {
    let suite = "PulseDeepSeekRender.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let directory = URL(fileURLWithPath: "/tmp/PulseDeepSeekRender", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let localURL = directory.appendingPathComponent("synthetic-tasks-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: localURL) }
    let localTasks = LocalTaskController(store: LocalTaskStore(fileURL: localURL))
    await localTasks.refresh()
    let added = await localTasks.saveTask(
      id: nil, text: "Review DeepSeek integration", tagIDs: [], newTagNames: ["Project"])
    XCTAssertTrue(added)
    let usages = [0, 1, 3, 20]
    for count in usages {
      let usage = UsageController(
        provider: RenderSnapshotProvider(snapshot: codexSnapshot(count: max(1, count))))
      let vipUsage = UsageController(
        provider: RenderSnapshotProvider(
          snapshot: moneySnapshot(
            provider: "88vip", amount: count == 0 ? "0" : count == 1 ? "104.22" : "123456789012.34",
            currency: "USD")))
      let deepSeekUsage = UsageController(
        provider: RenderSnapshotProvider(
          snapshot: moneySnapshot(
            provider: "deepseek",
            amount: count == 0 ? "0" : count == 1 ? "42.68" : "987654321098.76", currency: "CNY")
        ))
      await usage.refresh()
      await vipUsage.refresh()
      await deepSeekUsage.refresh()
      for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        let capture = HeaderFrameCapture()
        let root = home(
          defaults: defaults, localTasks: localTasks, usage: usage, vipUsage: vipUsage,
          deepSeekUsage: deepSeekUsage, pages: PopoverPageController()
        ).overlayPreferenceValue(ProviderHeaderBoundsKey.self) { anchors in
          GeometryReader { proxy in
            HeaderFrameCaptureView(
              frames: anchors.mapValues { proxy[$0] }, capture: capture)
          }
          .allowsHitTesting(false)
        }
        let host = NSHostingView(rootView: root)
        let bitmap = try render(host, appearance: appearance)
        let ids = [
          "openAIOverviewButton", "openSettingsButton",
          "focusTimerButton", "editRecordingButton", "openQuickCopyButton",
        ]
        XCTAssertEqual(Set(capture.frames.keys), Set(ids + ["tasksRegion"]))
        for id in ids {
          let frame = try XCTUnwrap(capture.frames[id], id)
          XCTAssertGreaterThanOrEqual(frame.minX, PulseDesignTokens.contentInset - 0.5, id)
          XCTAssertLessThanOrEqual(
            frame.maxX, HomeView.popoverSize.width - PulseDesignTokens.contentInset + 0.5, id)
          XCTAssertGreaterThan(frame.height, 20, id)
          for other in ids where other != id {
            let otherFrame = try XCTUnwrap(capture.frames[other])
            XCTAssertFalse(
              frame.insetBy(dx: 0.1, dy: 0.1).intersects(otherFrame), "\(id) overlaps \(other)")
          }
        }
        let settings = try XCTUnwrap(capture.frames["openSettingsButton"])
        let focusTimer = try XCTUnwrap(capture.frames["focusTimerButton"])
        let clip = try XCTUnwrap(capture.frames["editRecordingButton"])
        let copy = try XCTUnwrap(capture.frames["openQuickCopyButton"])
        XCTAssertLessThanOrEqual(clip.maxX, focusTimer.minX)
        XCTAssertLessThanOrEqual(focusTimer.maxX, copy.minX)
        XCTAssertLessThanOrEqual(copy.maxX, settings.minX)
        for frame in [clip, copy] {
          XCTAssertEqual(frame.width, focusTimer.width, accuracy: 1)
          XCTAssertEqual(frame.height, focusTimer.height, accuracy: 0.5)
          XCTAssertEqual(frame.midY, focusTimer.midY, accuracy: 0.5)
        }
        XCTAssertEqual(focusTimer.midY, settings.midY, accuracy: 0.5)
        let tasks = try XCTUnwrap(capture.frames["tasksRegion"])
        let ai = try XCTUnwrap(capture.frames["openAIOverviewButton"])
        XCTAssertGreaterThanOrEqual(tasks.minY, settings.maxY)
        XCTAssertLessThan(tasks.minY, 55, "The task region starts directly below the toolbar")
        XCTAssertGreaterThan(tasks.height, 400, "Tasks get most of the available vertical space")
        XCTAssertGreaterThanOrEqual(ai.minY + 0.5, tasks.maxY)
        XCTAssertEqual(ai.minX, PulseDesignTokens.contentInset, accuracy: 0.5)
        XCTAssertEqual(ai.height, 34, accuracy: 0.5)
        XCTAssertLessThanOrEqual(ai.maxY, HomeView.popoverSize.height - 7.5)
        let name = "\(appearance.rawValue)-home-\(count)-windows"
        try save(bitmap, to: directory.appendingPathComponent("\(name).png"))
        let frames = capture.frames.mapValues { NSStringFromRect($0) }
        let data = try JSONSerialization.data(
          withJSONObject: frames, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("\(name)-frames.json"))
      }
    }
  }

  #if DEBUG
    func testFocusTimerKeepsItsFrameWhenRunningInBothLanguages() throws {
      let suite = "PulseFocusTimerRender.\(UUID())"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let localTasks = LocalTaskController(
        store: LocalTaskStore(
          fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")))
      let usage = UsageController(provider: InactiveSettingsProvider())
      let timer = FocusTimerController()
      let root = home(
        defaults: defaults, localTasks: localTasks, usage: usage, vipUsage: usage,
        deepSeekUsage: usage, pages: PopoverPageController(), focusTimer: timer)
      for language in ["en", "zh-Hans"] {
        try PulseLocalization.$previewLanguage.withValue(language) {
          let capture = HeaderFrameCapture()
          let view = root.overlayPreferenceValue(ProviderHeaderBoundsKey.self) { anchors in
            GeometryReader { proxy in
              HeaderFrameCaptureView(frames: anchors.mapValues { proxy[$0] }, capture: capture)
            }
            .allowsHitTesting(false)
          }
          _ = try render(NSHostingView(rootView: view), appearance: .aqua)
          let idle = try XCTUnwrap(capture.frames["focusTimerButton"])
          timer.start()
          defer { timer.cancel() }
          _ = try render(NSHostingView(rootView: view), appearance: .aqua)
          let running = try XCTUnwrap(capture.frames["focusTimerButton"])
          XCTAssertEqual(idle.minX, running.minX, accuracy: 0.5, language)
          XCTAssertEqual(idle.width, running.width, accuracy: 0.5, language)
          XCTAssertEqual(idle.height, running.height, accuracy: 0.5, language)
        }
      }
    }
  #endif

  func testOverviewPlacesEachProviderOnItsOwnRowAndGeminiDetailsRender() async throws {
    let suite = "PulseGeminiRender.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let localTasks = LocalTaskController(
      store: LocalTaskStore(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")))
    let usage = UsageController(provider: RenderSnapshotProvider(snapshot: codexSnapshot(count: 1)))
    let vip = UsageController(
      provider: RenderSnapshotProvider(
        snapshot: moneySnapshot(provider: "88vip", amount: "104.22", currency: "USD")))
    let deepSeek = UsageController(
      provider: RenderSnapshotProvider(
        snapshot: moneySnapshot(provider: "deepseek", amount: "42.68", currency: "CNY")))
    let gemini = UsageController(
      provider: RenderSnapshotProvider(
        snapshot: UsageSnapshot(
          providerID: "antigravity", fetchedAt: .now,
          metrics: zip(AntigravityQuotaBucket.allCases, [71, 84, 99]).map { bucket, percent in
            .quota(
              QuotaWindow(
                durationMinutes: bucket.durationMinutes, remainingPercent: percent, resetsAt: .now,
                bucketID: bucket.rawValue, displayNameKey: bucket.displayNameKey))
          })))
    for controller in [usage, vip, deepSeek, gemini] { await controller.refresh() }

    let providers = [
      ProviderUsagePresentation(provider: .codex, usage: usage),
      ProviderUsagePresentation(provider: .vip, usage: vip),
      ProviderUsagePresentation(provider: .deepSeek, usage: deepSeek),
      ProviderUsagePresentation(provider: .antigravity, usage: gemini),
    ]
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      let capture = HeaderFrameCapture()
      let overview = AIUsageOverviewView(
        providers: providers, onOpenProvider: { _ in }, onConfigureProvider: { _ in },
        onManage: {}
      )
      .padding(.horizontal, PulseDesignTokens.contentInset)
      .overlayPreferenceValue(ProviderHeaderBoundsKey.self) { anchors in
        GeometryReader { proxy in
          HeaderFrameCaptureView(frames: anchors.mapValues { proxy[$0] }, capture: capture)
        }
        .allowsHitTesting(false)
      }
      _ = try render(NSHostingView(rootView: overview), appearance: appearance)
      var lastBottom: CGFloat?
      for id in [
        "openUsageButton", "openVIPUsageButton", "openDeepSeekUsageButton",
        "openAntigravityUsageButton",
      ] {
        let row = try XCTUnwrap(capture.frames[id], id)
        XCTAssertGreaterThanOrEqual(row.minX, PulseDesignTokens.contentInset - 0.5)
        XCTAssertLessThanOrEqual(
          row.maxX, HomeView.popoverSize.width - PulseDesignTokens.contentInset + 0.5)
        XCTAssertGreaterThan(row.height, 32, id)
        if let lastBottom { XCTAssertGreaterThanOrEqual(row.minY, lastBottom, id) }
        lastBottom = row.maxY
      }

      let pages = PopoverPageController()
      pages.showUsage(.antigravity)
      let root = home(
        defaults: defaults, localTasks: localTasks, usage: usage, vipUsage: vip,
        deepSeekUsage: deepSeek, pages: pages, antigravityUsage: gemini)
      let bitmap = try render(NSHostingView(rootView: root), appearance: appearance)
      XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }
  }

  func testDeepSeekStatesUsageAndSettingsRenderInBothAppearances() async throws {
    let suite = "PulseDeepSeekStates.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let directory = URL(fileURLWithPath: "/tmp/PulseDeepSeekRender", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let localTasks = LocalTaskController(
      store: LocalTaskStore(
        fileURL: directory.appendingPathComponent("unused-\(UUID()).json")))
    let usage = UsageController(provider: RenderSnapshotProvider(snapshot: codexSnapshot(count: 1)))
    let vip = UsageController(
      provider: RenderSnapshotProvider(
        snapshot: moneySnapshot(
          provider: "88vip", amount: "104.22", currency: "USD")))
    await usage.refresh()
    await vip.refresh()
    var multiCurrency = moneySnapshot(provider: "deepseek", amount: "42.68", currency: "CNY")
    multiCurrency = UsageSnapshot(
      providerID: multiCurrency.providerID, fetchedAt: multiCurrency.fetchedAt,
      metrics: multiCurrency.metrics + [.balance(amount: Decimal(string: "3.21")!, currency: "USD")]
    )
    let states: [(String, UsageController)] =
      [
        ("loading", UsageController(provider: RenderSnapshotProvider(snapshot: multiCurrency))),
        ("CNY-and-USD", UsageController(provider: RenderSnapshotProvider(snapshot: multiCurrency))),
        (
          "USD",
          UsageController(
            provider: RenderSnapshotProvider(
              snapshot: moneySnapshot(
                provider: "deepseek", amount: "104.22", currency: "USD")))
        ),
      ]
      + [
        DeepSeekUsageError.missingAPIKey, .invalidCredentials, .rateLimited, .networkUnavailable,
        .timedOut, .invalidResponse,
      ].map { error in
        (String(describing: error), UsageController(provider: RenderErrorProvider(error: error)))
      }
    for (name, controller) in states where name != "loading" { await controller.refresh() }
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      for (name, controller) in states {
        for page in [PopoverPage.home, .aiOverview, .usage(.deepSeek), .tagManagement] {
          let pages = PopoverPageController()
          switch page {
          case .home: break
          case .aiOverview: pages.showAIOverview()
          case .usage(let provider): pages.showUsage(provider)
          case .clipTask: pages.showClipTask()
          case .tagManagement: pages.showTagManagement()
          case .quickCopy: pages.showQuickCopy()
          }
          let host = NSHostingView(
            rootView: home(
              defaults: defaults, localTasks: localTasks, usage: usage, vipUsage: vip,
              deepSeekUsage: controller, pages: pages))
          let bitmap = try render(host, appearance: appearance)
          XCTAssertEqual(
            Double(bitmap.pixelsWide) * HomeView.popoverSize.height,
            Double(bitmap.pixelsHigh) * HomeView.popoverSize.width, accuracy: 1)
          for point in [(2, 2), (bitmap.pixelsWide - 2, bitmap.pixelsHigh - 2)] {
            XCTAssertEqual(
              try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1)).alphaComponent, 1,
              accuracy: 0.01)
          }
          if ["CNY-and-USD", "USD", "missingAPIKey", "invalidCredentials"].contains(name) {
            try save(
              bitmap,
              to: directory.appendingPathComponent(
                "\(appearance.rawValue)-\(name)-\(pageName(page)).png"))
          }
        }
      }
      // Settings evidence uses its real independent-window dimensions.
      let settings = SettingsView(
        config: AppConfig(defaults: defaults, loginItemService: RenderLoginItems()),
        deepSeekConfiguration: DeepSeekConfiguration(secretStore: RenderSecrets()),
        vipConfiguration: VIPConfiguration(secretStore: RenderSecrets()),
        localTasks: localTasks,
        updates: makeInactiveUpdateController(defaults: defaults),
        destination: .providers, onBack: {}, onDeepSeekCredentialsChanged: {},
        onVIPCredentialsChanged: {}, onQuit: {})
      let host = NSHostingView(
        rootView: settings.background(Color(nsColor: .windowBackgroundColor)))
      host.appearance = try XCTUnwrap(NSAppearance(named: appearance))
      host.frame = NSRect(origin: .zero, size: SettingsWindowController.contentSize)
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try save(
        bitmap,
        to: directory.appendingPathComponent("\(appearance.rawValue)-settings-all-controls.png"))
    }
  }

  private func home(
    defaults: UserDefaults, localTasks: LocalTaskController, usage: UsageController,
    vipUsage: UsageController, deepSeekUsage: UsageController, pages: PopoverPageController,
    antigravityUsage: UsageController? = nil, focusTimer: FocusTimerController? = nil
  ) -> HomeView {
    let deepSeekConfiguration = DeepSeekConfiguration(secretStore: RenderSecrets())
    let vipConfiguration = VIPConfiguration(secretStore: RenderSecrets())
    let config = AppConfig(defaults: defaults, loginItemService: RenderLoginItems())
    config.setAntigravityEnabled(antigravityUsage != nil)
    deepSeekConfiguration.refresh()
    vipConfiguration.refresh()
    return HomeView(
      config: config,
      usage: usage, vipUsage: vipUsage, deepSeekUsage: deepSeekUsage,
      deepSeekConfiguration: deepSeekConfiguration,
      vipConfiguration: vipConfiguration,
      localTasks: localTasks,
      updates: makeInactiveUpdateController(defaults: defaults),
      pages: pages, onDeepSeekCredentialsChanged: {}, onVIPCredentialsChanged: {},
      onQuit: {},
      clips: ClipController.production(defaults: defaults, live: false),
      focusTimer: focusTimer ?? FocusTimerController(),
      antigravityUsage: antigravityUsage ?? UsageController(provider: InactiveSettingsProvider()),
      quickCopy: QuickCopyController(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("PulseToolbarTest.json"),
        writeToClipboard: { _ in false }))
  }

  private func render<Content: View>(
    _ host: NSHostingView<Content>, appearance: NSAppearance.Name,
    height: CGFloat = HomeView.popoverSize.height
  ) throws -> NSBitmapImageRep {
    host.appearance = try XCTUnwrap(NSAppearance(named: appearance))
    host.frame = NSRect(x: 0, y: 0, width: HomeView.popoverSize.width, height: height)
    host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return bitmap
  }

  private func save(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
  }

  private func pageName(_ page: PopoverPage) -> String {
    switch page {
    case .home: "home"
    case .aiOverview: "ai-overview"
    case .usage: "usage"
    case .clipTask: "clip"
    case .tagManagement: "tags"
    case .quickCopy: "quick copy"
    }
  }

  private func codexSnapshot(count: Int) -> UsageSnapshot {
    UsageSnapshot(
      providerID: "codex", fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
      metrics: (0..<count).map { index in
        .quota(
          QuotaWindow(
            durationMinutes: index == 0 ? 300 : 10_080 * index,
            remainingPercent: index == 0 ? 100 : 72, resetsAt: nil))
      })
  }

  private func moneySnapshot(provider: String, amount: String, currency: String) -> UsageSnapshot {
    UsageSnapshot(
      providerID: provider, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
      metrics: [.balance(amount: Decimal(string: amount)!, currency: currency)])
  }
}

@MainActor
private final class HeaderFrameCapture {
  var frames: [String: CGRect] = [:]
}

private struct HeaderFrameCaptureView: NSViewRepresentable {
  let frames: [String: CGRect]
  let capture: HeaderFrameCapture
  func makeNSView(context: Context) -> NSView {
    capture.frames = frames
    return NSView()
  }
  func updateNSView(_ nsView: NSView, context: Context) { capture.frames = frames }
}

private struct RenderSnapshotProvider: UsageProviding {
  let snapshot: UsageSnapshot
  func fetch() async throws -> UsageSnapshot { snapshot }
}

private struct RenderErrorProvider: UsageProviding {
  let error: DeepSeekUsageError
  func fetch() async throws -> UsageSnapshot { throw error }
}

private struct RenderSecrets: SecretStoring {
  func read(account: String) throws -> String? { "synthetic-render-key" }
  func save(_ secret: String, account: String) throws {}
  func delete(account: String) throws {}
}

@MainActor
private final class RenderLoginItems: LoginItemManaging {
  var status: LoginItemStatus { .notRegistered }
  func setEnabled(_ enabled: Bool) throws {}
}
