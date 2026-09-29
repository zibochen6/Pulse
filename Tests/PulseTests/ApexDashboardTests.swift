import Foundation
import XCTest

@testable import Pulse

@MainActor
final class ApexDashboardTests: XCTestCase {
  func testParserReadsVerifiedApexStructureFromFixture() throws {
    let fileURL = try fixtureURL()
    let dashboard = try ApexDashboardParser().parse(contents: String(contentsOf: fileURL), fileURL: fileURL)

    XCTAssertEqual(dashboard.columns.map(\.title), ["Inbox", "Workstreams", "参考"])
    XCTAssertEqual(dashboard.columns[0].cards.map(\.title), ["Sample checklist", "Spare notes"])
    XCTAssertEqual(dashboard.columns[0].cards[0].tasks.map(\.text), [
      "Draft a fictional outline", "Review a sample document",
    ])
    XCTAssertFalse(dashboard.columns[0].cards[0].tasks[0].completed)
    XCTAssertTrue(dashboard.columns[0].cards[0].tasks[1].completed)
    XCTAssertEqual(dashboard.columns[0].cards[0].tasks[0].lineNumber, 23)
    XCTAssertEqual(dashboard.columns[2].cards, [])
  }

  func testParserPreservesExplicitBlockIdentifier() throws {
    let contents = """
    ---
    dashboard: true
    columns:
      - name: 收集
        color: \"#123456\"
        type: todo
    ---
    ## 收集
    ### Card
    - [ ] Keep a stable anchor ^task-anchor
    """

    let dashboard = try ApexDashboardParser().parse(
      contents: contents, fileURL: URL(fileURLWithPath: "/tmp/example.md")
    )
    let task = try XCTUnwrap(dashboard.columns.first?.cards.first?.tasks.first)
    XCTAssertEqual(task.text, "Keep a stable anchor")
    XCTAssertEqual(task.blockIdentifier, "task-anchor")
  }

  func testParserRejectsTaskOutsideCard() {
    let contents = """
    ---
    dashboard: true
    columns:
      - name: Inbox
        color: \"#123456\"
        type: todo
    ---
    ## Inbox
    - [ ] An ungrouped task
    """

    XCTAssertThrowsError(
      try ApexDashboardParser().parse(contents: contents, fileURL: URL(fileURLWithPath: "/tmp/example.md"))
    ) { error in
      XCTAssertEqual(error as? DashboardParseError, .taskOutsideCard(line: 9))
    }
  }

  func testParserRejectsColumnHeadingMissingFromFrontmatter() {
    let contents = """
    ---
    dashboard: true
    columns:
      - name: Inbox
        color: \"#123456\"
        type: todo
    ---
    ## Other
    """

    XCTAssertThrowsError(
      try ApexDashboardParser().parse(contents: contents, fileURL: URL(fileURLWithPath: "/tmp/example.md"))
    ) { error in
      XCTAssertEqual(error as? DashboardParseError, .undeclaredColumn("Other"))
    }
  }

  func testBookmarkConfigurationAndControllerReloadSelectedFile() async throws {
    let suiteName = "PulseApexTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated defaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let temporaryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("pulse-apex-\(UUID().uuidString).md")
    defer { try? FileManager.default.removeItem(at: temporaryURL) }
    try String(contentsOf: try fixtureURL()).write(to: temporaryURL, atomically: true, encoding: .utf8)

    let configuration = DashboardConfiguration(defaults: defaults)
    let controller = DashboardTaskController(configuration: configuration)
    await controller.saveDashboard(url: temporaryURL)

    guard case .loaded(let dashboard) = controller.state else {
      return XCTFail("Expected selected Dashboard to load")
    }
    XCTAssertEqual(dashboard.columns.count, 3)

    let restoredConfiguration = DashboardConfiguration(defaults: defaults)
    XCTAssertTrue(restoredConfiguration.hasDashboardSelection)
    XCTAssertEqual(try restoredConfiguration.resolveDashboardURL().standardizedFileURL, temporaryURL.standardizedFileURL)

    try "not an Apex Dashboard".write(to: temporaryURL, atomically: true, encoding: .utf8)
    await controller.refresh()
    guard case .parseError = controller.state else {
      return XCTFail("Expected malformed content to replace the loaded snapshot")
    }

    try FileManager.default.removeItem(at: temporaryURL)
    await controller.refresh()
    XCTAssertEqual(controller.state, .fileMissing)
  }

  func testObsidianURIOnlyOpensTheSourceFile() {
    let fileURL = URL(fileURLWithPath: "/tmp/Notes/Task list.md")
    guard let url = ObsidianURLOpener.url(for: fileURL), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return XCTFail("Could not create Obsidian URI")
    }
    XCTAssertEqual(components.scheme, "obsidian")
    XCTAssertEqual(components.host, "open")
    XCTAssertEqual(components.queryItems, [URLQueryItem(name: "path", value: fileURL.path)])
    XCTAssertNil(components.fragment)
  }

  private func fixtureURL() throws -> URL {
    guard let url = Bundle(for: Self.self).url(forResource: "sample-apex-dashboard", withExtension: "md") else {
      throw XCTSkip("Apex fixture is not bundled in this test target")
    }
    return url
  }
}
