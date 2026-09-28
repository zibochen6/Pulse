import AppKit
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class HomeViewRenderingTests: XCTestCase {
  func testCodexMenuIconIsBundled() {
    XCTAssertNotNil(Bundle.main.url(forResource: "CodexMenuIcon", withExtension: "png"))
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
    await usage.refresh()

    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      guard let appearance = NSAppearance(named: appearanceName) else {
        return XCTFail("Could not create \(appearanceName) appearance")
      }
      for page in [
        PopoverPage.home, .usage, .settings(.general), .settings(.providers),
        .settings(.tasks), .settings(.about),
      ] {
        let pages = PopoverPageController()
        switch page {
        case .home: break
        case .usage: pages.showUsage()
        case .settings(let destination): pages.showSettings(destination)
        }
        let host = NSHostingView(
          rootView: HomeView(
            config: config, usage: usage, pages: pages, onQuit: {}
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

  func testHomeRendersLoadingMultipleWindowsAndLongErrorsInBothAppearances() async {
    let suiteName = "PulseRenderingStates.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated defaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let config = AppConfig(defaults: defaults, loginItemService: PreviewLoginItemService())

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
        for page in [PopoverPage.home, .usage] {
          let pages = PopoverPageController()
          if page == .usage { pages.showUsage() }
          let host = NSHostingView(
            rootView: HomeView(config: config, usage: usage, pages: pages, onQuit: {})
          )
          host.appearance = appearance
          host.frame = NSRect(origin: .zero, size: HomeView.popoverSize)
          host.layoutSubtreeIfNeeded()
          guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return XCTFail("Could not render \(page) with usage state \(usage.state)")
          }
          host.cacheDisplay(in: host.bounds, to: bitmap)
          XCTAssertEqual(host.bounds.size, HomeView.popoverSize)
          XCTAssertEqual(bitmap.pixelsWide * 510, bitmap.pixelsHigh * 360)
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
