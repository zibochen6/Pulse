import AppKit
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class TagBarLayoutTests: XCTestCase {
  func testPinnedTodoUsesIntrinsicWidthAndOverflowControlsAreVisible() async throws {
    let tags = ["工作", "发布", "灵感", "生活", "阅读", "以后"].map { TaskTag(name: $0) }
    let controller = LocalTaskController(store: TagLayoutStore(tags: tags))
    await controller.refresh()
    let presentation = LocalTaskPresentation()
    presentation.selectedFilter = .tag(try XCTUnwrap(tags.first).id)
    let capture = TagBarFrameCapture()
    let host = NSHostingView(
      rootView: LocalTasksView(
        controller: controller, presentation: presentation, onEditingChanged: { _ in }
      )
      .frame(width: 400, height: 400)
      .overlayPreferenceValue(LocalTagBarBoundsKey.self) { anchors in
        GeometryReader { geometry in
          TagBarFrameCaptureView(frames: anchors.mapValues { geometry[$0] }, capture: capture)
        }
        .allowsHitTesting(false)
      })
    let window = NSWindow(
      contentRect: NSRect(x: -16_000, y: -16_000, width: 400, height: 400),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    // The scroll-view metrics arrive after attachment, then reveal both arrows.
    let controls = ["todo", "previous", "next", "add", "manage"]
    for _ in 0..<40 {
      host.layoutSubtreeIfNeeded()
      if controls.allSatisfy({ capture.frames[$0]?.isEmpty == false }) { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    let todo = try XCTUnwrap(capture.frames["todo"])
    XCTAssertLessThan(todo.width, 80, "The pinned Todo must keep its intrinsic width")
    var previousFrame: CGRect?
    for control in controls {
      let frame = try XCTUnwrap(capture.frames[control], "Missing tag control: \(control)")
      XCTAssertGreaterThan(frame.width, 0, control)
      XCTAssertGreaterThanOrEqual(frame.height, 18, control)
      XCTAssertTrue(host.bounds.contains(frame), "\(control) must remain visible: \(frame)")
      if let previousFrame {
        XCTAssertGreaterThanOrEqual(frame.minX, previousFrame.maxX, "Tag controls must not overlap")
        XCTAssertEqual(frame.midY, previousFrame.midY, accuracy: 1, "Tag controls share one row")
      }
      previousFrame = frame
    }
  }
}

@MainActor
private final class TagBarFrameCapture {
  var frames: [String: CGRect] = [:]
}

private struct TagBarFrameCaptureView: NSViewRepresentable {
  let frames: [String: CGRect]
  let capture: TagBarFrameCapture
  func makeNSView(context: Context) -> NSView {
    capture.frames = frames
    return NSView()
  }
  func updateNSView(_ nsView: NSView, context: Context) { capture.frames = frames }
}

private struct TagLayoutStore: LocalTaskStoring {
  let tags: [TaskTag]
  func load() async throws -> LocalTaskSnapshot {
    LocalTaskSnapshot(document: LocalTaskDocument(tags: tags))
  }
  func mutate(_ mutation: LocalTaskMutation) async throws -> LocalTaskSnapshot { try await load() }
}
