import AppKit
import Combine
import XCTest

@testable import Pulse

@MainActor
final class ClipControllerTests: XCTestCase {
  func testEmptyOrPreviouslyClearedDownloadsDoNotStartCodex() async throws {
    let data = try Fixture()
    defer { data.clean() }
    let clips = data.controller()
    try Data([1]).write(to: data.downloads.appendingPathComponent("work-demo.mp4"))
    clips.start()
    try await until { clips.snapshot.phase == .noClip }
    try Data([1]).write(to: data.downloads.appendingPathComponent("IMG_12.mov"))
    data.defaults.set(
      Date.now.addingTimeInterval(2).timeIntervalSince1970, forKey: "clipIgnoreAddedThrough")
    clips.start()
    try await until { clips.snapshot.phase == .noClip }
    XCTAssertFalse(FileManager.default.fileExists(atPath: data.support.path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: data.root.appendingPathComponent("invoked").path))
  }

  func testFinderSelectionUsesArrivalOrderAndIgnoresLookalikes() throws {
    let data = try Fixture()
    defer { data.clean() }
    for name in ["IMG_55.MOV", "rec_23.Mp4", "rec_24.mp4.part", "work-demo.mp4", "IMG_2.mp4"] {
      try Data([1]).write(to: data.downloads.appendingPathComponent(name))
    }
    let old = data.downloads.appendingPathComponent("IMG_55.MOV")
    try FileManager.default.setAttributes(
      [.modificationDate: Date.distantPast], ofItemAtPath: old.path)
    try FileManager.default.createSymbolicLink(
      at: data.downloads.appendingPathComponent("rec_99.MP4"),
      withDestinationURL: old)
    let selected = try XCTUnwrap(RecordingSelection.latest(in: data.downloads))
    XCTAssertEqual(selected.lastPathComponent, "rec_23.Mp4")
  }

  func testLiveEventsDedupSettingsSnapshotAndRecoveryAcrossViews() async throws {
    let data = try Fixture()
    defer { data.clean() }
    try Data([7]).write(to: data.downloads.appendingPathComponent("rec_101.mp4"))
    let clips = data.controller()
    clips.start()
    let id = clips.snapshot.id
    clips.start()
    clips.model = "next-model"
    clips.effort = "high"
    XCTAssertEqual(clips.snapshot.id, id)
    try await until {
      FileManager.default.fileExists(atPath: data.root.appendingPathComponent("invoked").path)
    }
    XCTAssertEqual(clips.snapshot.phase, .starting)
    try data.signal("begin")
    try await until { clips.snapshot.phase == .running }
    XCTAssertEqual(clips.snapshot.model, "gpt-6.2-sol")
    XCTAssertEqual(clips.snapshot.effort, "low")
    XCTAssertFalse(clips.canMarkResultDone)
    clips.markResultDone(id: id)
    let reopened = data.controller()
    reopened.restore()
    reopened.start()
    XCTAssertEqual(reopened.snapshot.id, id)
    XCTAssertEqual(reopened.snapshot.phase, .running)
    XCTAssertEqual(reopened.model, "next-model")
    try data.signal("finish")
    try await until { clips.snapshot.phase == .attention && reopened.snapshot.phase == .attention }
    XCTAssertTrue(clips.canMarkResultDone)
    XCTAssertFalse(clips.isResultDone)
    XCTAssertEqual(clips.snapshot.platforms.count, 4)
    XCTAssertEqual(clips.snapshot.platforms.first?.status, "needs_login")
    XCTAssertEqual(clips.snapshot.platforms.last?.status, "page_only")
    XCTAssertNotNil(clips.snapshot.folderURL)
    XCTAssertNotNil(clips.snapshot.reviewURL)
    let invocations = try String(
      contentsOf: data.root.appendingPathComponent("invoked"), encoding: .utf8)
    XCTAssertEqual(invocations.split(separator: "\n").count, 1)
    XCTAssertTrue(invocations.contains("--model gpt-6.2-sol"))
    XCTAssertTrue(invocations.contains(#"model_reasoning_effort="low""#))
  }

  func testCLIExitStopsActivityAndKeepsJobFiles() async throws {
    let data = try Fixture()
    defer { data.clean() }
    try Data([7]).write(to: data.downloads.appendingPathComponent("rec_101.mp4"))
    try data.signal("begin")
    try data.signal("abort")
    let clips = data.controller()
    clips.start()
    try await until { clips.snapshot.phase == .failed }
    XCTAssertNotNil(clips.snapshot.folderURL)
    XCTAssertFalse(clips.snapshot.phase.isActive)
    XCTAssertTrue(clips.snapshot.detail?.contains("19") == true)
  }

  func testStoppedWorkerPublishesFailureAndItsExplanationTogether() throws {
    let data = try Fixture()
    defer { data.clean() }
    try FileManager.default.createDirectory(at: data.support, withIntermediateDirectories: true)
    let running = ClipSnapshot(phase: .running, source: "rec_101.mp4")
    try JSONEncoder().encode(running).write(to: data.support.appendingPathComponent("latest.json"))

    let clips = data.controller()
    var failures: [ClipSnapshot] = []
    let changes = clips.$snapshot.sink {
      if $0.phase == .failed { failures.append($0) }
    }
    clips.restore()

    withExtendedLifetime(changes) {
      XCTAssertEqual(failures, [clips.snapshot])
      XCTAssertFalse(failures.first?.detail?.isEmpty ?? true)
    }
  }

  func testDoneHidesOnlyTheSelectedResultAndSurvivesRestart() throws {
    let data = try Fixture()
    defer { data.clean() }
    try FileManager.default.createDirectory(at: data.support, withIntermediateDirectories: true)
    let review = data.root.appendingPathComponent("review.html")
    try Data("Review".utf8).write(to: review)
    let latest = data.support.appendingPathComponent("latest.json")
    let result = ClipSnapshot(
      phase: .attention, source: "rec_101.mp4", folder: data.root.path, review: review.path)
    let original = try JSONEncoder().encode(result)
    try original.write(to: latest)

    let clips = data.controller()
    clips.restore()
    XCTAssertTrue(clips.canMarkResultDone)
    clips.markResultDone(id: "old-result")
    XCTAssertFalse(clips.isResultDone)
    clips.markResultDone(id: result.id)
    XCTAssertTrue(clips.isResultDone)
    XCTAssertEqual(try Data(contentsOf: latest), original)

    let reopened = data.controller()
    reopened.restore()
    XCTAssertTrue(reopened.isResultDone)
    XCTAssertEqual(reopened.snapshot, result)
    XCTAssertEqual(reopened.previousResult, result)
    XCTAssertEqual(reopened.snapshot.reviewURL, review.resolvingSymlinksInPath())

    // A different run of the same recording gets its own Home status.
    let next = ClipSnapshot(phase: .completed, source: result.source)
    try JSONEncoder().encode(next).write(to: latest)
    reopened.restore()
    XCTAssertEqual(reopened.snapshot.id, next.id)
    XCTAssertTrue(reopened.canMarkResultDone)
    reopened.markResultDone(id: result.id)
    XCTAssertFalse(reopened.isResultDone)
    reopened.markResultDone(id: next.id)
    XCTAssertTrue(reopened.isResultDone)
  }

  private func until(_ predicate: @MainActor () -> Bool) async throws {
    let limit = Date.now.addingTimeInterval(10)
    while !predicate(), Date.now < limit { try await Task.sleep(for: .milliseconds(30)) }
    guard predicate() else { throw NSError(domain: "Timed out waiting for clip fixture", code: 1) }
  }

  @MainActor private final class Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Pulse clip \(UUID())")
    let suite = "Pulse.ClipTests.\(UUID())"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    var downloads: URL { root.appendingPathComponent("Downloads") }
    var support: URL { root.appendingPathComponent("Support") }

    init() throws {
      let skill = root.appendingPathComponent(ClipController.skill)
      for url in [skill.deletingLastPathComponent(), downloads] {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      }
      try Data().write(to: skill)
      defaults.set(root.path, forKey: "clipWorkspace")
      let fake = root.appendingPathComponent("synthetic-codex")
      try Self.script.write(to: fake, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
    }

    func controller() -> ClipController {
      let fake = root.appendingPathComponent("synthetic-codex").path
      return ClipController(
        defaults: defaults, support: support, downloads: downloads, live: true,
        tools: { (URL(fileURLWithPath: "/usr/bin/python3"), fake) })
    }

    func signal(_ name: String) throws { try Data().write(to: root.appendingPathComponent(name)) }

    func clean() {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: root)
    }

    static let script = #"""
      #!/bin/sh
      cat >/dev/null
      echo "$*" >> invoked
      while [ "$1" != "--output-last-message" ]; do shift; done
      result="$2"
      while [ ! -f begin ]; do sleep 0.03; done
      echo '{"type":"turn.started"}'
      if [ -f abort ]; then exit 19; fi
      while [ ! -f finish ]; do sleep 0.03; done
      mkdir -p output/rec_101/publish
      echo review > output/rec_101/publish/review.html
      echo '{"outcome":"blocked","message":"Fixture","review":"publish/review.html","platforms":{"douyin":{"status":"needs_login"},"bilibili":{"status":"page_only"}}}' > "$result"
      echo '{"type":"turn.completed"}'
      """#
  }
}
