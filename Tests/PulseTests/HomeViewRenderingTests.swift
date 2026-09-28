import AppKit
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class HomeViewRenderingTests: XCTestCase {
  func testCodexMenuIconIsBundled() {
    XCTAssertNotNil(Bundle.main.url(forResource: "CodexMenuIcon", withExtension: "png"))
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
      let host = NSHostingView(rootView: HomeView(config: config, usage: usage, onQuit: {}))
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
