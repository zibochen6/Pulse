import Foundation
import XCTest

@testable import Pulse

@MainActor
final class TaskSourceConfigurationTests: XCTestCase {
  private func defaults() throws -> UserDefaults {
    let name = "PulseTaskSource.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    addTeardownBlock { defaults.removePersistentDomain(forName: name) }
    return defaults
  }

  func testFreshInstallDefaultsToLocalAndPersistsChoice() throws {
    let defaults = try defaults()
    let config = TaskSourceConfiguration(defaults: defaults)
    XCTAssertEqual(config.source, .local)
    XCTAssertEqual(defaults.string(forKey: "taskSource"), "local")
  }

  func testExistingBookmarkMigratesToApexWithoutReadingOrChangingBookmark() throws {
    let defaults = try defaults()
    let bookmark = Data("isolated fake bookmark".utf8)
    defaults.set(bookmark, forKey: "apexDashboardBookmark")
    let config = TaskSourceConfiguration(defaults: defaults)
    XCTAssertEqual(config.source, .apex)
    XCTAssertEqual(defaults.data(forKey: "apexDashboardBookmark"), bookmark)
    XCTAssertEqual(defaults.string(forKey: "taskSource"), "apex")
  }

  func testExplicitSourceSurvivesBookmarkAdditionRemovalAndReload() throws {
    let defaults = try defaults()
    let config = TaskSourceConfiguration(defaults: defaults)
    defaults.set(Data([1]), forKey: "apexDashboardBookmark")
    XCTAssertEqual(TaskSourceConfiguration(defaults: defaults).source, .local)
    config.setSource(.apex)
    defaults.removeObject(forKey: "apexDashboardBookmark")
    XCTAssertEqual(TaskSourceConfiguration(defaults: defaults).source, .apex)
    config.setSource(.local)
    XCTAssertEqual(TaskSourceConfiguration(defaults: defaults).source, .local)
  }

  func testUnknownPreferenceUsesSafeMigrationDefault() throws {
    let defaults = try defaults()
    defaults.set("unknown", forKey: "taskSource")
    defaults.set(Data([1]), forKey: "apexDashboardBookmark")
    XCTAssertEqual(TaskSourceConfiguration(defaults: defaults).source, .apex)
    XCTAssertEqual(defaults.string(forKey: "taskSource"), "apex")
  }
}
