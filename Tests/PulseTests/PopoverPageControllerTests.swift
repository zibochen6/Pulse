import XCTest

@testable import Pulse

@MainActor
final class PopoverPageControllerTests: XCTestCase {
  func testPageTransitionsAndReset() {
    let pages = PopoverPageController()
    XCTAssertEqual(pages.page, .home)
    for provider in ProviderID.allCases {
      pages.showUsage(provider)
      XCTAssertEqual(pages.page, .usage(provider))
      pages.showHome()
      XCTAssertEqual(pages.page, .home)
    }
    pages.showTagManagement()
    XCTAssertEqual(pages.page, .tagManagement)
    pages.reset()
    XCTAssertEqual(pages.page, .home)
  }

  func testSelectingTheCurrentPageDoesNotPublishAnotherTransition() {
    let pages = PopoverPageController()
    var changes: [PopoverPage] = []
    let subscription = pages.$page.dropFirst().sink { changes.append($0) }

    pages.reset()
    pages.showUsage(.codex)
    pages.showUsage(.codex)
    pages.showHome()
    pages.reset()

    withExtendedLifetime(subscription) {
      XCTAssertEqual(changes, [.usage(.codex), .home])
    }
  }

  func testSettingsNavigationDoesNotResetWithPopover() {
    let pages = PopoverPageController()
    let settings = SettingsPresentation()
    settings.open(.providers, provider: .deepSeek)
    pages.showUsage(.vip)
    pages.reset()
    XCTAssertEqual(pages.page, .home)
    XCTAssertEqual(settings.destination, .providers)
    XCTAssertEqual(settings.focusedProvider, .deepSeek)
  }

  /// Settings reports one aggregated editing bit: the tag editor and the two
  /// API key fields hold focus in turn, and the popover's dismissal suspension
  /// has to survive that hand-off instead of being released the moment the
  /// first control blurs.
  func testEditingRegistryAggregatesEverySettingsSurface() {
    let registry = PulseEditingRegistry()
    XCTAssertFalse(registry.isEditing)

    registry.set(source: "tagEditor", editing: true)
    XCTAssertTrue(registry.isEditing)

    registry.set(source: "deepSeekAPIKeyField", editing: true)
    XCTAssertTrue(registry.isEditing)

    registry.set(source: "tagEditor", editing: false)
    XCTAssertTrue(registry.isEditing, "Blurring one field must not release the suspension")

    registry.set(source: "deepSeekAPIKeyField", editing: false)
    XCTAssertFalse(registry.isEditing)

    registry.set(source: "vipAPIKeyField", editing: true)
    registry.clear()
    XCTAssertFalse(registry.isEditing, "Leaving the page always releases it")

    // Repeated reports from the same source are idempotent.
    registry.set(source: "vipAPIKeyField", editing: true)
    registry.set(source: "vipAPIKeyField", editing: true)
    XCTAssertTrue(registry.isEditing)
    registry.set(source: "vipAPIKeyField", editing: false)
    XCTAssertFalse(registry.isEditing)
  }
}
