import AppKit
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class HomeViewRenderingTests: XCTestCase {
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
            config: config,
            usage: usage,
            vipUsage: vipUsage,
            vipConfiguration: vipConfiguration,
            pages: pages,
            onVIPCredentialsChanged: {},
            onQuit: {}
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
        for page in [PopoverPage.home, .usage] {
          let pages = PopoverPageController()
          if page == .usage { pages.showUsage() }
          let host = NSHostingView(
            rootView: HomeView(
              config: config,
              usage: usage,
              vipUsage: vipUsage,
              vipConfiguration: vipConfiguration,
              pages: pages,
              onVIPCredentialsChanged: {},
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
            vipConfiguration: vipConfiguration,
            pages: pages,
            onVIPCredentialsChanged: {},
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
    throw PreviewUsageError(isUnavailable: false, userMessage: "88VIP is rate-limiting balance requests.")
  }
}

private final class PreviewSecretStore: SecretStoring, @unchecked Sendable {
  func read(account: String) throws -> String? { nil }
  func save(_ secret: String, account: String) throws {}
  func delete(account: String) throws {}
}
