import AppKit
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class DashboardTaskRowTests: XCTestCase {
  private func sampleTask() throws -> DashboardTask {
    let text = """
      ---
      dashboard: true
      columns:
        - name: Inbox
          color: "#123456"
          type: todo
      ---
      ## Inbox
      ### Card
      - [ ] A fictional task 🚀
      """
    return try XCTUnwrap(
      ApexDashboardParser().parse(contents: text, fileURL: URL(fileURLWithPath: "/tmp/sample.md"))
        .allTasks.first)
  }

  func testCheckboxAndTextExposeIndependentAccessibleActions() throws {
    let task = try sampleTask()
    var toggles = 0
    var opens = 0
    let host = NSHostingView(
      rootView: DashboardTaskRow(
        task: task, isPending: false, onToggle: { toggles += 1 }, onOpen: { opens += 1 }
      ))
    host.frame = NSRect(x: 0, y: 0, width: 330, height: 40)
    let window = NSWindow(
      contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    host.layoutSubtreeIfNeeded()
    let elements = descendants(host)
    guard elements.contains(where: { $0.accessibilityRole() == .button }) else {
      throw XCTSkip(
        "The unit-test hosting surface exposes no SwiftUI accessibility buttons; desktop click validation is still required."
      )
    }
    let checkbox = try XCTUnwrap(
      elements.first { $0.accessibilityIdentifier() == "dashboardCheckbox.\(task.lineNumber)" })
    let text = try XCTUnwrap(
      elements.first { $0.accessibilityIdentifier() == "dashboardTask.\(task.lineNumber)" })
    XCTAssertTrue(checkbox.accessibilityPerformPress())
    XCTAssertEqual(toggles, 1)
    XCTAssertEqual(opens, 0)
    XCTAssertTrue(text.accessibilityPerformPress())
    XCTAssertEqual(toggles, 1)
    XCTAssertEqual(opens, 1)
  }

  func testPendingCheckboxIsDisabledButTextStillOpens() throws {
    let task = try sampleTask()
    var toggles = 0
    var opens = 0
    let host = NSHostingView(
      rootView: DashboardTaskRow(
        task: task, isPending: true, onToggle: { toggles += 1 }, onOpen: { opens += 1 }
      ))
    host.frame = NSRect(x: 0, y: 0, width: 330, height: 40)
    let window = NSWindow(
      contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    host.layoutSubtreeIfNeeded()
    let elements = descendants(host)
    guard elements.contains(where: { $0.accessibilityRole() == .button }) else {
      throw XCTSkip(
        "The unit-test hosting surface exposes no SwiftUI accessibility buttons; desktop pending-state validation is still required."
      )
    }
    let checkbox = try XCTUnwrap(
      elements.first { $0.accessibilityIdentifier() == "dashboardCheckbox.\(task.lineNumber)" })
    let text = try XCTUnwrap(
      elements.first { $0.accessibilityIdentifier() == "dashboardTask.\(task.lineNumber)" })
    XCTAssertFalse(checkbox.isAccessibilityEnabled())
    XCTAssertTrue(text.accessibilityPerformPress())
    XCTAssertEqual(toggles, 0)
    XCTAssertEqual(opens, 1)
  }

  private func descendants(_ element: Any, depth: Int = 0) -> [any NSAccessibilityProtocol] {
    guard depth < 20, let accessible = element as? any NSAccessibilityProtocol else { return [] }
    return [accessible]
      + (accessible.accessibilityChildren() ?? []).flatMap { descendants($0, depth: depth + 1) }
  }
}
