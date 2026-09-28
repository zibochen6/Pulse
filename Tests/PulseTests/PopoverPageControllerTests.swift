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
}
