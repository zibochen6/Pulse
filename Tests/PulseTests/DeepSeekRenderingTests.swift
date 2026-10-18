import AppKit
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class DeepSeekRenderingTests: XCTestCase {
  func testActualHeaderFramesAndRepresentativeRendersInBothAppearances() async throws {
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
          "openUsageButton", "openVIPUsageButton", "openDeepSeekUsageButton", "openSettingsButton",
        ]
        XCTAssertEqual(Set(capture.frames.keys), Set(ids))
        for id in ids {
          let frame = try XCTUnwrap(capture.frames[id], id)
          XCTAssertGreaterThanOrEqual(frame.minX, 13.5, id)
          XCTAssertLessThanOrEqual(frame.maxX, 346.5, id)
          XCTAssertGreaterThan(frame.height, 20, id)
          for other in ids where other != id {
            let otherFrame = try XCTUnwrap(capture.frames[other])
            XCTAssertFalse(
              frame.insetBy(dx: 0.1, dy: 0.1).intersects(otherFrame), "\(id) overlaps \(other)")
          }
        }
        let codex = try XCTUnwrap(capture.frames["openUsageButton"])
        if count == 0 {
          let settings = try XCTUnwrap(capture.frames["openSettingsButton"])
          XCTAssertEqual(
            codex.midY, settings.midY, accuracy: 0.5, "Compact controls share the brand row")
          XCTAssertLessThan(codex.minX, 140, "Flexible space follows the indicators")
        } else {
          XCTAssertEqual(
            codex.minX, 14, accuracy: 0.5, "Fallback indicators start at the leading inset")
        }
        let vip = try XCTUnwrap(capture.frames["openVIPUsageButton"])
        let deepSeek = try XCTUnwrap(capture.frames["openDeepSeekUsageButton"])
        for (frame, title) in [
          (vip, VIPUsageFormatter.title(for: vipUsage.state)),
          (deepSeek, DeepSeekUsageFormatter.title(for: deepSeekUsage.state)),
        ] {
          let textWidth = (title as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
          ]).width
          XCTAssertGreaterThanOrEqual(frame.width, textWidth + 23, "Every amount digit fits")
        }
        if count > 1 {
          XCTAssertGreaterThan(
            deepSeek.minY, codex.minY, "Wide indicators wrap as complete controls")
        }
        if count == 20 {
          XCTAssertLessThanOrEqual(
            codex.width, 332.5, "Oversized quota stays in a bounded scroll area")
        }
        let name = "\(appearance.rawValue)-home-\(count)-windows"
        try save(bitmap, to: directory.appendingPathComponent("\(name).png"))
        let frames = capture.frames.mapValues { NSStringFromRect($0) }
        let data = try JSONSerialization.data(
          withJSONObject: frames, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("\(name)-frames.json"))
      }
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
        for page in [PopoverPage.home, .usage, .settings(.providers)] {
          let pages = PopoverPageController()
          switch page {
          case .home: break
          case .usage: pages.showUsage()
          case .settings: pages.showSettings(.providers)
          }
          let host = NSHostingView(
            rootView: home(
              defaults: defaults, localTasks: localTasks, usage: usage, vipUsage: vip,
              deepSeekUsage: controller, pages: pages))
          let bitmap = try render(host, appearance: appearance)
          XCTAssertEqual(bitmap.pixelsWide * 510, bitmap.pixelsHigh * 360)
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
      // Full controls evidence at the same width; product remains 360 × 510.
      let settings = SettingsView(
        config: AppConfig(defaults: defaults, loginItemService: RenderLoginItems()),
        deepSeekConfiguration: DeepSeekConfiguration(secretStore: RenderSecrets()),
        vipConfiguration: VIPConfiguration(secretStore: RenderSecrets()),
        tasks: DashboardTaskController(configuration: DashboardConfiguration(defaults: defaults)),
        localTasks: localTasks, taskSource: TaskSourceConfiguration(defaults: defaults),
        dashboardPicker: DashboardFilePicker(
          closePopover: { false }, onSelection: { _ in }, onFinish: {}),
        destination: .providers, onBack: {}, onDeepSeekCredentialsChanged: {},
        onVIPCredentialsChanged: {},
        onSelectDashboardFile: {}, onQuit: {})
      let host = NSHostingView(
        rootView: settings.background(Color(nsColor: .windowBackgroundColor)))
      let bitmap = try render(host, appearance: appearance, height: 1100)
      try save(
        bitmap,
        to: directory.appendingPathComponent("\(appearance.rawValue)-settings-all-controls.png"))
    }
  }

  private func home(
    defaults: UserDefaults, localTasks: LocalTaskController, usage: UsageController,
    vipUsage: UsageController, deepSeekUsage: UsageController, pages: PopoverPageController
  ) -> HomeView {
    HomeView(
      config: AppConfig(defaults: defaults, loginItemService: RenderLoginItems()),
      usage: usage, vipUsage: vipUsage, deepSeekUsage: deepSeekUsage,
      deepSeekConfiguration: DeepSeekConfiguration(secretStore: RenderSecrets()),
      vipConfiguration: VIPConfiguration(secretStore: RenderSecrets()),
      tasks: DashboardTaskController(configuration: DashboardConfiguration(defaults: defaults)),
      localTasks: localTasks, taskSource: TaskSourceConfiguration(defaults: defaults),
      dashboardPicker: DashboardFilePicker(
        closePopover: { false }, onSelection: { _ in }, onFinish: {}),
      pages: pages, onDeepSeekCredentialsChanged: {}, onVIPCredentialsChanged: {},
      onSelectDashboardFile: {}, onOpenDashboardFile: { _ in true }, onQuit: {})
  }

  private func render<Content: View>(
    _ host: NSHostingView<Content>, appearance: NSAppearance.Name, height: CGFloat = 510
  ) throws -> NSBitmapImageRep {
    host.appearance = try XCTUnwrap(NSAppearance(named: appearance))
    host.frame = NSRect(x: 0, y: 0, width: 360, height: height)
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
    case .usage: "usage"
    case .settings: "settings"
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
