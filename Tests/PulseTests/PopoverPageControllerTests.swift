import XCTest

@testable import Pulse

@MainActor
final class PopoverPageControllerTests: XCTestCase {
  func testPageTransitionsAndReset() {
    let pages = PopoverPageController()
    XCTAssertEqual(pages.page, .home)

    pages.showUsage()
    XCTAssertEqual(pages.page, .usage)
    pages.showHome()
    XCTAssertEqual(pages.page, .home)

    pages.showSettings(.tasks)
    XCTAssertEqual(pages.page, .settings(.tasks))
    pages.reset()
    XCTAssertEqual(pages.page, .home)
  }

  func testAllSettingsEntrypointsReturnHome() {
    let pages = PopoverPageController()
    for destination in [
      SettingsDestination.general, .providers, .tasks, .about,
    ] {
      pages.showSettings(destination)
      XCTAssertEqual(pages.page, .settings(destination))
      pages.showHome()
      XCTAssertEqual(pages.page, .home)
    }
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
