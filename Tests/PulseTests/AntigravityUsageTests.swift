import Darwin
import Foundation
import XCTest

@testable import Pulse

@MainActor
final class AntigravityUsageTests: XCTestCase {
  private let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

  func testDecodesThreeDistinctBucketsAndUsesOnlyFiveHourInSummary() throws {
    let snapshot = try decode(
      Self.report(
        """
        {"id":"gemini-weekly","remaining_fraction":0.731,"reset_time":"2026-11-29T08:37:26Z"},
        {"id":"gemini-argon-wtu-weekly","remaining_fraction":1,"reset_time":"2026-11-30T05:31:23.123Z"},
        {"id":"gemini-5h","remaining_fraction":0,"reset_time":"2026-11-23T06:40:45Z"}
        """))
    XCTAssertEqual(snapshot.providerID, "antigravity")
    XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    XCTAssertEqual(
      snapshot.quotaWindows.map(\.bucketID),
      [
        "gemini-5h", "gemini-weekly", "gemini-argon-wtu-weekly",
      ])
    XCTAssertEqual(snapshot.quotaWindows.map(\.durationMinutes), [300, 10_080, 10_080])
    XCTAssertEqual(snapshot.quotaWindows.map(\.remainingPercent), [0, 73, 100])
    XCTAssertEqual(
      snapshot.quotaWindows.first?.resetsAt, Date(timeIntervalSince1970: 1_795_416_045))
    XCTAssertTrue(snapshot.quotaWindows.allSatisfy { $0.resetsAt != nil })
    XCTAssertEqual(AntigravityStatusSummary.title(for: .success(snapshot)), "0%")
  }

  func testUnknownOrDisabledFiveHourDoesNotSubstituteWeekly() throws {
    for bucket in [
      #"{"id":"gemini-5h","disabled":true,"remaining_fraction":1}"#,
      #"{"id":"gemini-5h","reset_time":"2026-11-23T06:40:45Z"}"#,
      #"{"id":"gemini-5h","remaining_fraction":1.3,"reset_time":"2026-11-23T06:40:45Z"}"#,
    ] {
      let snapshot = try decode(
        Self.report(
          """
          \(bucket),
          {"id":"gemini-weekly","remaining_fraction":0.92},
          {"id":"gemini-argon-wtu-weekly","remaining_fraction":0.88}
          """))
      XCTAssertEqual(AntigravityStatusSummary.title(for: .success(snapshot)), "--")
      XCTAssertEqual(snapshot.quotaWindows.suffix(2).map(\.remainingPercent), [92, 88])
    }
  }

  func testEmptyAndInvalidReportsDifferFromFailedConnections() throws {
    XCTAssertThrowsError(
      try decode(Self.report(#"{"id":"anthropic-weekly","remaining_fraction":0.5}"#))
    ) { XCTAssertEqual($0 as? AntigravityUsageError, .noQuota) }
    XCTAssertThrowsError(try decode("noise")) {
      XCTAssertEqual($0 as? AntigravityUsageError, .invalidReport)
    }
    XCTAssertThrowsError(
      try decode(Self.report("").replacingOccurrences(of: "usage", with: "other"))
    ) {
      XCTAssertEqual($0 as? AntigravityUsageError, .invalidReport)
    }
    for (diagnostic, expected): (String, AntigravityUsageError) in [
      ("Eligibility check failed: Antigravity is not available in your location.", .notEligible),
      ("Eligibility check failed", .queryFailed),
      ("sign in to Antigravity", .signInRequired),
      ("request timed out", .timeout),
      ("Eligibility check failed: dial tcp: i/o timeout", .timeout),
      ("connection refused", .network),
      (#"Eligibility check failed: Get "https://example.invalid": EOF"#, .network),
      ("Eligibility check failed: dial tcp: lookup example.invalid: no such host", .network),
      ("Eligibility check failed: read tcp: connection reset by peer", .network),
    ] {
      let body = try JSONSerialization.data(withJSONObject: [
        "status": "ERROR", "error": diagnostic,
      ])
      let result = AntigravityCLIResult(status: 1, stdout: body, stderr: Data())
      XCTAssertThrowsError(try AntigravityProvider.decode(result, fetchedAt: fetchedAt)) {
        XCTAssertEqual($0 as? AntigravityUsageError, expected, diagnostic)
      }
    }
  }

  func testStopResetsStateAndPreventsQueuedRefresh() async throws {
    let provider = CountingUsageProvider()
    let controller = UsageController(provider: provider)
    await controller.refresh()
    guard case .success = controller.state else { return XCTFail("Expected a successful refresh") }
    let pending = controller.requestRefresh()
    controller.stop(reset: true)
    await pending.value
    let count = await provider.count
    XCTAssertEqual(count, 1)
    XCTAssertEqual(controller.state, .loading)
    XCTAssertFalse(controller.isRefreshing)
  }

  func testTransportUsesOnlyLocalReadOnlyCommandInAnIsolatedDirectory() async throws {
    let json = Self.report(#"{"id":"gemini-5h","remaining_fraction":0.713}"#)
    let script = """
      [ "$AGY_CLI_DISABLE_AUTO_UPDATE" = true ] || exit 10
      [ -z "${GEMINI_API_KEY+x}" ] && [ -z "${GOOGLE_API_KEY+x}" ] || exit 11
      if [ "$1" = --version ]; then
        echo 1.1.11
        exit
      fi
      [ "$#" = 7 ] || exit 12
      [ "$*" = '--disable-slash-commands=false -p /usage --output-format json --print-timeout 12s' ] || exit 13
      [ "$BROWSER" -ef "$PWD/open" ] && [ "$(command -v open)" -ef "$PWD/open" ] || exit 14
      "$BROWSER" example.invalid && exit 15
      printf '%s' '\(json)'
      """
    let fixture = try makeCLI(script)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let result = try await fixture.transport.readUsage()
    XCTAssertEqual(result.status, 0)
    let snapshot = try AntigravityProvider.decode(result, fetchedAt: fetchedAt)
    XCTAssertEqual(snapshot.quotaWindows.first?.remainingPercent, 71)
  }

  func testTransportDoesNotRunUsageOnAnOldCLI() async throws {
    let fixture = try makeCLI(
      """
      if [ "$1" = --version ]; then
        echo 1.1.10
      else
        : > "$PULSE_TEST_ROOT/usage-was-called"
      fi
      """)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    do {
      _ = try await fixture.transport.readUsage()
      XCTFail("Old CLI accepted")
    } catch { XCTAssertEqual(error as? AntigravityUsageError, .unsupportedCLI) }
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("usage-was-called").path))
  }

  func testTransportTimesOutAndReapsItsProcess() async throws {
    let fixture = try makeCLI(Self.slowCLI, timeout: .milliseconds(500))
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    do {
      _ = try await fixture.transport.readUsage()
      XCTFail("Idle CLI should time out")
    } catch { XCTAssertEqual(error as? AntigravityUsageError, .timeout) }
    XCTAssertEqual(Darwin.kill(try childPID(in: fixture.root), 0), -1)
  }

  func testTransportCleansUpHelperAfterTheCLIReturns() async throws {
    let fixture = try makeCLI(
      """
      if [ "$1" = --version ]; then
        echo 1.5.14
        exit
      fi
      /bin/sleep 30 &
      echo "$!" > "$PULSE_TEST_ROOT/pid"
      /bin/sleep 0.05
      """, timeout: .milliseconds(500))
    defer {
      if let pid = try? childPID(in: fixture.root) { _ = Darwin.kill(pid, SIGKILL) }
      try? FileManager.default.removeItem(at: fixture.root)
    }
    do {
      _ = try await fixture.transport.readUsage()
      XCTFail("A helper keeping the CLI pipes open should time out")
    } catch { XCTAssertEqual(error as? AntigravityUsageError, .timeout) }

    let pid = try childPID(in: fixture.root)
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while Darwin.kill(pid, 0) == 0 && clock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(Darwin.kill(pid, 0), -1)
  }

  func testTransportReapsItsProcessOnCancellation() async throws {
    let fixture = try makeCLI(Self.slowCLI)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let query = Task { try await fixture.transport.readUsage() }
    defer { query.cancel() }
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(4)
    var pid: pid_t?
    while pid == nil && clock.now < deadline {
      pid = try? childPID(in: fixture.root)
      if pid == nil { try await Task.sleep(for: .milliseconds(10)) }
    }
    let processID = try XCTUnwrap(pid)
    query.cancel()
    do {
      _ = try await query.value
      XCTFail("Cancelled CLI query returned data")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(Darwin.kill(processID, 0), -1)
  }

  private func decode(_ json: String) throws -> UsageSnapshot {
    let result = AntigravityCLIResult(status: 0, stdout: Data(json.utf8), stderr: Data())
    return try AntigravityProvider.decode(result, fetchedAt: fetchedAt)
  }

  private static func report(_ buckets: String) -> String {
    """
    {
      "status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"buckets":[
      \(buckets)
      ]}]}}
    }
    """
  }

  private static let slowCLI = """
    if [ "$1" = --version ]; then
      echo 1.5.14
      exit
    fi
    echo "$$" > "$PULSE_TEST_ROOT/pid"
    exec /bin/sleep 30
    """

  private func makeCLI(
    _ script: String, timeout: Duration = .seconds(10)
  ) throws -> (root: URL, transport: AntigravityCLITransport) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Pulse-Fake-AGY-\(UUID())", isDirectory: true)
    let bin = root.appendingPathComponent(".local/bin", isDirectory: true)
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let executable = bin.appendingPathComponent("agy")
    try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let environment = [
      "PATH": "/usr/bin:/bin", "PULSE_TEST_ROOT": root.path,
      "GEMINI_API_KEY": "synthetic-unused", "GOOGLE_API_KEY": "synthetic-unused",
    ]
    return (
      root, AntigravityCLITransport(environment: environment, home: root.path, timeout: timeout)
    )
  }

  private func childPID(in root: URL) throws -> pid_t {
    let file = root.appendingPathComponent("pid")
    let pid = try String(contentsOf: file, encoding: .utf8)
    return try XCTUnwrap(pid_t(pid.trimmingCharacters(in: .whitespacesAndNewlines)))
  }
}

private actor CountingUsageProvider: UsageProviding {
  private(set) var count = 0
  func fetch() async throws -> UsageSnapshot {
    count += 1
    return UsageSnapshot(
      providerID: "antigravity", fetchedAt: .now,
      metrics: [.quota(QuotaWindow(durationMinutes: 300, remainingPercent: 52, resetsAt: nil))])
  }
}
