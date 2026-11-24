import AppKit
import QuartzCore
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class HomeViewRenderingTests: XCTestCase {
  private func isolatedLocalTasks() -> LocalTaskController {
    LocalTaskController(
      store: LocalTaskStore(
        fileURL:
          FileManager.default.temporaryDirectory.appendingPathComponent(
            "PulseRender-\(UUID()).json")))
  }

  private func inactiveDeepSeekUsage() -> UsageController {
    UsageController(provider: PreviewVIPUsageProvider())
  }

  func testTodayPopoverUsesMeasuredContentWithAHeightCap() {
    XCTAssertEqual(HomeView.popoverSize, NSSize(width: 400, height: 520))
    XCTAssertEqual(HomeView.sizeForToday(header: 97, tasks: 220.2), NSSize(width: 400, height: 318))
    XCTAssertEqual(HomeView.sizeForToday(header: 97, tasks: 600), HomeView.popoverSize)
    XCTAssertEqual(HomeView.sizeForToday(header: 97, tasks: nil), HomeView.popoverSize)
    XCTAssertEqual(HomeView.sizeForToday(header: 0, tasks: 220), HomeView.popoverSize)
  }

  func testPopoverBodySwapsInPlaceAndSkipsFadeWithReduceMotion() throws {
    let content = PopoverContentTransition<PopoverPage, Text>.Container(
      rootView: AnyView(Text("Home")), page: .home)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: HomeView.popoverSize),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.ignoresMouseEvents = true
    window.contentView = content
    window.setFrameOrigin(NSPoint(x: -16_000, y: -16_000))
    window.orderFront(nil)
    defer { window.close() }

    let host = try XCTUnwrap(content.subviews.first)
    let layer = try XCTUnwrap(host.layer)
    content.update(rootView: AnyView(Text("Usage")), page: .usage(.codex), reduceMotion: false)
    XCTAssertEqual(content.subviews, [host], "Do not capture or retain an outgoing page")
    let fade = try XCTUnwrap(layer.animation(forKey: "pageOpacity") as? CABasicAnimation)
    XCTAssertEqual(fade.duration, PulseDesignTokens.contentFadeDuration)
    XCTAssertEqual(try XCTUnwrap(fade.fromValue as? NSNumber).doubleValue, 0.90, accuracy: 0.001)

    content.update(rootView: AnyView(Text("Tags")), page: .tagManagement, reduceMotion: true)
    XCTAssertEqual(content.subviews, [host])
    XCTAssertNil(layer.animation(forKey: "pageOpacity"))
    XCTAssertEqual(layer.opacity, 1)
  }

  func testCodexMenuIconIsBundled() {
    XCTAssertNotNil(Bundle.main.url(forResource: "CodexMenuIcon", withExtension: "png"))
  }

  func testCodexColorIconIsBundledWithTransparentCorners() {
    guard let url = Bundle.main.url(forResource: "CodexColorIcon", withExtension: "png"),
      let image = NSImage(contentsOf: url),
      let data = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: data),
      let corner = bitmap.colorAt(x: 0, y: 0)
    else {
      return XCTFail("Could not load the color Codex icon")
    }

    XCTAssertLessThan(corner.alphaComponent, 0.01)
  }

  func testThirdPartyNoticesAreBundled() {
    XCTAssertNotNil(Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"))
  }

  func testHomeViewCoversPopoverSurfaceInBothAppearances() async {
    let suiteName = "PulseRenderingTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated defaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let config = AppConfig(defaults: defaults, loginItemService: PreviewLoginItemService())
    let usage = UsageController(provider: PreviewUsageProvider())
    let vipUsage = UsageController(provider: PreviewVIPUsageProvider())
    let vipConfiguration = VIPConfiguration(secretStore: PreviewSecretStore())
    await usage.refresh()
    await vipUsage.refresh()

    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      guard let appearance = NSAppearance(named: appearanceName) else {
        return XCTFail("Could not create \(appearanceName) appearance")
      }
      for page in [
        PopoverPage.home, .usage(.codex), .usage(.vip), .usage(.deepSeek), .tagManagement,
        .clipTask,
      ] {
        let pages = PopoverPageController()
        switch page {
        case .home: break
        case .usage(let provider): pages.showUsage(provider)
        case .clipTask: pages.showClipTask()
        case .tagManagement: pages.showTagManagement()
        }
        let host = NSHostingView(
          rootView: HomeView(
            config: config,
            usage: usage,
            vipUsage: vipUsage,
            deepSeekUsage: inactiveDeepSeekUsage(),
            deepSeekConfiguration: DeepSeekConfiguration(secretStore: PreviewSecretStore()),
            vipConfiguration: vipConfiguration,
            localTasks: isolatedLocalTasks(),
            updates: makeInactiveUpdateController(defaults: defaults),
            pages: pages,
            onDeepSeekCredentialsChanged: {}, onVIPCredentialsChanged: {},
            onQuit: {}, clips: ClipController.production(defaults: defaults, live: false)
          )
        )
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: HomeView.popoverSize)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
          return XCTFail("Could not render HomeView")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 4, height > 4 else { return XCTFail("Empty HomeView render") }
        let points = [
          (2, 2), (width - 2, 2), (2, height - 2), (width - 2, height - 2),
          (width / 2, height / 2),
        ]
        for point in points {
          guard let color = bitmap.colorAt(x: point.0, y: point.1) else {
            return XCTFail("Missing rendered pixel")
          }
          XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01)
        }
      }
    }
  }

  func testNativeWindowPaperRevealsBackdropThroughTheCards() async throws {
    let suite = "PulsePopoverPaper.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let config = AppConfig(defaults: defaults, loginItemService: PreviewLoginItemService())
    let usage = inactiveDeepSeekUsage()
    let localTasks = isolatedLocalTasks()
    await localTasks.refresh()
    for index in 1...8 {
      let saved = await localTasks.saveTask(
        id: nil, text: "Sample task \(index)", tagIDs: [], newTagNames: [])
      XCTAssertTrue(saved)
    }
    let home = HomeView(
      config: config, usage: usage, vipUsage: usage, deepSeekUsage: usage,
      deepSeekConfiguration: DeepSeekConfiguration(secretStore: PreviewSecretStore()),
      vipConfiguration: VIPConfiguration(secretStore: PreviewSecretStore()),
      localTasks: localTasks, updates: makeInactiveUpdateController(defaults: defaults),
      pages: PopoverPageController(), onDeepSeekCredentialsChanged: {},
      onVIPCredentialsChanged: {}, onQuit: {}
    ).environment(\.pulseHasNativeBackdrop, true)

    let settings = SettingsView(
      config: config,
      deepSeekConfiguration: DeepSeekConfiguration(secretStore: PreviewSecretStore()),
      vipConfiguration: VIPConfiguration(secretStore: PreviewSecretStore()),
      localTasks: isolatedLocalTasks(), updates: makeInactiveUpdateController(defaults: defaults),
      onDeepSeekCredentialsChanged: {}, onVIPCredentialsChanged: {}, onQuit: {}
    ).environment(\.pulseHasNativeBackdrop, true)

    func verifyBackdrop<V: View>(
      _ surface: V, size: NSSize, appearance: NSAppearance, cardY: CGFloat, cardInset: CGFloat
    ) throws {
      func visibleBackdrop() throws -> (margin: CGFloat, card: CGFloat) {
        let host = NSHostingView(
          rootView: ZStack {
            HStack(spacing: 0) {
              Color.red
              Color.blue
            }
            surface
          }
        )
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        func contrastBetweenHalves(inset: Int, y: Int) throws -> CGFloat {
          let left = try XCTUnwrap(bitmap.colorAt(x: inset, y: y)?.usingColorSpace(.deviceRGB))
          let right = try XCTUnwrap(
            bitmap.colorAt(x: bitmap.pixelsWide - inset - 1, y: y)?.usingColorSpace(.deviceRGB))
          return abs(left.redComponent - right.redComponent)
            + abs(left.blueComponent - right.blueComponent)
        }
        let inset = Int(cardInset * Double(bitmap.pixelsWide) / size.width)
        let y = Int(cardY * Double(bitmap.pixelsHigh) / size.height)
        return (
          try contrastBetweenHalves(inset: 3, y: 3), try contrastBetweenHalves(inset: inset, y: y)
        )
      }
      config.setWindowTransparencyPercent(0)
      let solid = try visibleBackdrop()
      XCTAssertEqual(solid.margin, 0, accuracy: 0.01)
      XCTAssertEqual(solid.card, 0, accuracy: 0.01)
      config.setWindowTransparencyPercent(10)
      let low = try visibleBackdrop()
      XCTAssertGreaterThan(low.card, 0.08)
      XCTAssertGreaterThan(low.margin, 0.2)
      config.setWindowTransparencyPercent(25)
      let midpoint = try visibleBackdrop()
      XCTAssertGreaterThan(midpoint.card, low.card)
      config.setWindowTransparencyPercent(50)
      let maximum = try visibleBackdrop()
      XCTAssertGreaterThan(maximum.card, midpoint.card)
      XCTAssertGreaterThan(maximum.margin, midpoint.margin)
      config.setSystemReducesTransparency(true)
      let reduced = try visibleBackdrop()
      XCTAssertEqual(reduced.margin, solid.margin, accuracy: 0.01)
      XCTAssertEqual(reduced.card, solid.card, accuracy: 0.01)
      config.setSystemReducesTransparency(false)
    }

    for name in [NSAppearance.Name.aqua, .darkAqua] {
      let appearance = try XCTUnwrap(NSAppearance(named: name))
      try verifyBackdrop(
        home, size: HomeView.popoverSize, appearance: appearance, cardY: 260, cardInset: 21)
      try verifyBackdrop(
        settings, size: SettingsWindowController.contentSize, appearance: appearance,
        cardY: 190, cardInset: 140)
    }
  }

  func testHomeRendersLoadingMultipleWindowsAndLongErrorsInBothAppearances() async {
    let suiteName = "PulseRenderingStates.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated defaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let config = AppConfig(defaults: defaults, loginItemService: PreviewLoginItemService())
    let vipUsage = UsageController(provider: PreviewVIPUsageProvider())
    let vipConfiguration = VIPConfiguration(secretStore: PreviewSecretStore())
    await vipUsage.refresh()

    let providers: [any UsageProviding] = [
      PreviewUsageProvider(), MultipleWindowUsageProvider(), UnavailableUsageProvider(),
      FailedUsageProvider(),
    ]
    let loading = UsageController(provider: PreviewUsageProvider())
    let usages = [loading] + providers.map { UsageController(provider: $0) }
    for usage in usages.dropFirst() { await usage.refresh() }

    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      guard let appearance = NSAppearance(named: appearanceName) else {
        return XCTFail("Could not create \(appearanceName) appearance")
      }
      for usage in usages {
        for page in [PopoverPage.home, .usage(.codex)] {
          let pages = PopoverPageController()
          if case .usage(let provider) = page { pages.showUsage(provider) }
          let host = NSHostingView(
            rootView: HomeView(
              config: config,
              usage: usage,
              vipUsage: vipUsage,
              deepSeekUsage: inactiveDeepSeekUsage(),
              deepSeekConfiguration: DeepSeekConfiguration(secretStore: PreviewSecretStore()),
              vipConfiguration: vipConfiguration,
              localTasks: isolatedLocalTasks(),
              updates: makeInactiveUpdateController(defaults: defaults),
              pages: pages,
              onDeepSeekCredentialsChanged: {}, onVIPCredentialsChanged: {},
              onQuit: {}
            )
          )
          host.appearance = appearance
          host.frame = NSRect(origin: .zero, size: HomeView.popoverSize)
          host.layoutSubtreeIfNeeded()
          guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return XCTFail("Could not render \(page) with usage state \(usage.state)")
          }
          host.cacheDisplay(in: host.bounds, to: bitmap)
          XCTAssertEqual(host.bounds.size, HomeView.popoverSize)
          XCTAssertEqual(
            Double(bitmap.pixelsWide) * HomeView.popoverSize.height,
            Double(bitmap.pixelsHigh) * HomeView.popoverSize.width, accuracy: 1)
          for point in [(2, 2), (bitmap.pixelsWide - 2, bitmap.pixelsHigh - 2)] {
            guard let color = bitmap.colorAt(x: point.0, y: point.1) else {
              return XCTFail("Missing rendered pixel")
            }
            XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01)
          }
        }
      }
    }
  }

  func testVIPStatesRenderInBothAppearances() async {
    let suiteName = "PulseVIPRenderingStates.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated defaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let config = AppConfig(defaults: defaults, loginItemService: PreviewLoginItemService())
    let codexUsage = UsageController(provider: PreviewUsageProvider())
    await codexUsage.refresh()
    let vipConfiguration = VIPConfiguration(secretStore: PreviewSecretStore())
    let providers: [any UsageProviding] = [
      PreviewVIPUsageProvider(), VIPUnavailableUsageProvider(), VIPFailedUsageProvider(),
    ]
    let loading = UsageController(provider: PreviewVIPUsageProvider())
    let vipUsages = [loading] + providers.map { UsageController(provider: $0) }
    for vipUsage in vipUsages.dropFirst() { await vipUsage.refresh() }

    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      guard let appearance = NSAppearance(named: appearanceName) else {
        return XCTFail("Could not create \(appearanceName) appearance")
      }
      for vipUsage in vipUsages {
        let pages = PopoverPageController()
        let host = NSHostingView(
          rootView: HomeView(
            config: config,
            usage: codexUsage,
            vipUsage: vipUsage,
            deepSeekUsage: inactiveDeepSeekUsage(),
            deepSeekConfiguration: DeepSeekConfiguration(secretStore: PreviewSecretStore()),
            vipConfiguration: vipConfiguration,
            localTasks: isolatedLocalTasks(),
            updates: makeInactiveUpdateController(defaults: defaults),
            pages: pages,
            onDeepSeekCredentialsChanged: {}, onVIPCredentialsChanged: {},
            onQuit: {}
          )
        )
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: HomeView.popoverSize)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
          return XCTFail("Could not render 88VIP state \(vipUsage.state)")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let topLeft = bitmap.colorAt(x: 2, y: 2),
          let bottomRight = bitmap.colorAt(x: bitmap.pixelsWide - 2, y: bitmap.pixelsHigh - 2)
        else {
          return XCTFail("Missing rendered 88VIP pixels")
        }
        XCTAssertEqual(topLeft.alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(bottomRight.alphaComponent, 1, accuracy: 0.01)
      }
    }
  }

  func testBuiltInHomeAndTagSettingsRenderInBothAppearances() async throws {
    let suiteName = "PulseBuiltInHomeRender.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseBuiltInHome-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let localTasks = LocalTaskController(
      store: LocalTaskStore(fileURL: directory.appendingPathComponent("tasks.json")))
    await localTasks.refresh()
    let added = await localTasks.saveTask(
      id: nil,
      text:
        "Prepare a fictional demo 📝 with a deliberately long task title that wraps in the compact task list",
      tagIDs: [], newTagNames: ["Work"])
    XCTAssertTrue(added)
    let first = try XCTUnwrap(localTasks.document?.tasks.first)
    await localTasks.setCompleted(true, taskID: first.id)?.value
    let secondAdded = await localTasks.saveTask(
      id: nil, text: "Check a sample document", tagIDs: [], newTagNames: [])
    XCTAssertTrue(secondAdded)
    let usage = UsageController(provider: PreviewUsageProvider())
    let vipUsage = UsageController(provider: PreviewVIPUsageProvider())
    await usage.refresh()
    await vipUsage.refresh()
    let config = AppConfig(defaults: defaults, loginItemService: PreviewLoginItemService())
    let vipConfiguration = VIPConfiguration(secretStore: PreviewSecretStore())
    let renderDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseBuiltinTaskRender")
    try FileManager.default.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      for settings in [false, true] {
        let pages = PopoverPageController()
        if settings { pages.showTagManagement() }
        let host = NSHostingView(
          rootView: HomeView(
            config: config, usage: usage, vipUsage: vipUsage,
            deepSeekUsage: inactiveDeepSeekUsage(),
            deepSeekConfiguration: DeepSeekConfiguration(secretStore: PreviewSecretStore()),
            vipConfiguration: vipConfiguration,
            localTasks: localTasks,
            updates: makeInactiveUpdateController(defaults: defaults),
            pages: pages,
            onDeepSeekCredentialsChanged: {}, onVIPCredentialsChanged: {}, onQuit: {}))
        host.appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
        host.frame = NSRect(origin: .zero, size: HomeView.popoverSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(
          Double(bitmap.pixelsWide) * HomeView.popoverSize.height,
          Double(bitmap.pixelsHigh) * HomeView.popoverSize.width, accuracy: 1)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(
          to: renderDirectory.appendingPathComponent(
            "\(appearanceName.rawValue)-\(settings ? "settings" : "home").png"))
      }
    }
  }

  /// The Updates section sits below the popover fold, so it is rendered at full
  /// height to keep the verified status and actions visually inspectable.
  func testUpdatesSectionRendersAtFullHeightInBothAppearances() async throws {
    let suite = "PulseUpdatesRender.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseUpdatesRender")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let config = AppConfig(defaults: defaults, loginItemService: PreviewLoginItemService())
    let updates = makeInactiveUpdateController(defaults: defaults)
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      let view = SettingsView(
        config: config,
        deepSeekConfiguration: DeepSeekConfiguration(secretStore: PreviewSecretStore()),
        vipConfiguration: VIPConfiguration(secretStore: PreviewSecretStore()),
        localTasks: isolatedLocalTasks(),
        updates: updates,
        destination: .updates,
        onBack: {}, onDeepSeekCredentialsChanged: {}, onVIPCredentialsChanged: {},
        onQuit: {}
      )
      .frame(width: 720)
      .background(Color(nsColor: .windowBackgroundColor))
      let host = NSHostingView(rootView: view)
      host.appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
      host.frame = NSRect(origin: .zero, size: SettingsWindowController.contentSize)
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      for point in [(2, 2), (bitmap.pixelsWide - 2, bitmap.pixelsHigh - 2)] {
        let color = try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1))
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01)
      }
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      try png.write(
        to: directory.appendingPathComponent("\(appearanceName.rawValue)-updates.png"))
    }
  }

  func testVisibleSettingsActionsRenderInBothAppearances() async throws {
    let suite = "PulseSettingsButtons.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let config = AppConfig(defaults: defaults, loginItemService: PreviewLoginItemService())
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseSettingsActionRender")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      for destination in SettingsDestination.allCases {
        let session = SettingsPresentation(destination: destination)
        if destination == .providers { session.beginEditing(.deepSeek) }
        let host = NSHostingView(
          rootView: SettingsView(
            config: config,
            deepSeekConfiguration: DeepSeekConfiguration(secretStore: PreviewSecretStore()),
            vipConfiguration: VIPConfiguration(secretStore: PreviewConnectedSecretStore()),
            localTasks: isolatedLocalTasks(),
            updates: makeInactiveUpdateController(defaults: defaults),
            onDeepSeekCredentialsChanged: {}, onVIPCredentialsChanged: {}, onQuit: {},
            presentation: session))
        host.appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
        host.frame = NSRect(origin: .zero, size: SettingsWindowController.contentSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(host.bounds.size, NSSize(width: 720, height: 560))
        for point in [(2, 2), (bitmap.pixelsWide - 2, bitmap.pixelsHigh - 2)] {
          XCTAssertEqual(
            try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1)).alphaComponent, 1, accuracy: 0.01)
        }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(
          to: directory.appendingPathComponent("\(appearanceName.rawValue)-\(destination).png"))
      }
    }
  }

}

@MainActor
private final class PreviewLoginItemService: LoginItemManaging {
  var status: LoginItemStatus { .notRegistered }
  func setEnabled(_ enabled: Bool) throws {}
}

private struct PreviewUsageProvider: UsageProviding {
  func fetch() async throws -> UsageSnapshot {
    UsageSnapshot(
      providerID: "codex",
      fetchedAt: Date(),
      metrics: [
        .quota(
          QuotaWindow(
            durationMinutes: 300, remainingPercent: 94, resetsAt: Date().addingTimeInterval(5400))
        )
      ]
    )
  }
}

private struct MultipleWindowUsageProvider: UsageProviding {
  func fetch() async throws -> UsageSnapshot {
    UsageSnapshot(
      providerID: "codex",
      fetchedAt: Date(),
      metrics: [
        .quota(QuotaWindow(durationMinutes: 300, remainingPercent: 94, resetsAt: Date())),
        .quota(QuotaWindow(durationMinutes: 10_080, remainingPercent: 72, resetsAt: Date())),
        .quota(QuotaWindow(durationMinutes: 43_200, remainingPercent: 61, resetsAt: Date())),
      ]
    )
  }
}

private struct UnavailableUsageProvider: UsageProviding {
  func fetch() async throws -> UsageSnapshot {
    throw PreviewUsageError(isUnavailable: true, userMessage: "Codex is not signed in.")
  }
}

private struct FailedUsageProvider: UsageProviding {
  func fetch() async throws -> UsageSnapshot {
    throw PreviewUsageError(
      isUnavailable: false,
      userMessage: String(repeating: "The usage service could not be reached. ", count: 8)
    )
  }
}

private struct PreviewUsageError: UsageFailureDescribing {
  let isUnavailable: Bool
  let userMessage: String
}

private struct PreviewVIPUsageProvider: UsageProviding {
  func fetch() async throws -> UsageSnapshot {
    UsageSnapshot(
      providerID: VIPProvider.providerID,
      fetchedAt: Date(),
      metrics: [.balance(amount: 42.5, currency: "USD")]
    )
  }
}

private struct VIPUnavailableUsageProvider: UsageProviding {
  func fetch() async throws -> UsageSnapshot {
    throw PreviewUsageError(isUnavailable: true, userMessage: "Add an 88VIP API key in Settings.")
  }
}

private struct VIPFailedUsageProvider: UsageProviding {
  func fetch() async throws -> UsageSnapshot {
    throw PreviewUsageError(
      isUnavailable: false, userMessage: "88VIP is rate-limiting balance requests.")
  }
}

private final class PreviewSecretStore: SecretStoring, @unchecked Sendable {
  func read(account: String) throws -> String? { nil }
  func save(_ secret: String, account: String) throws {}
  func delete(account: String) throws {}
}

private struct PreviewConnectedSecretStore: SecretStoring {
  func read(account: String) throws -> String? { "fictional-render-only-key" }
  func save(_ secret: String, account: String) throws {}
  func delete(account: String) throws {}
}
