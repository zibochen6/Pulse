import Foundation
import XCTest

@testable import Pulse

final class CodexUsageTests: XCTestCase {
  func testSingleWindowUsesOnlyPercentageAndPreservesReset() throws {
    let snapshot = try decode(
      """
      {"result":{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":2,"windowDurationMins":10080,"resetsAt":1780000000}}}}}
      """)

    XCTAssertEqual(snapshot.providerID, "codex")
    XCTAssertEqual(UsageMenuFormatter.title(for: .success(snapshot)), "98%")
    XCTAssertEqual(snapshot.quotaWindows.first?.shortLabel, "7d")
    XCTAssertEqual(
      snapshot.quotaWindows.first?.resetsAt, Date(timeIntervalSince1970: 1_780_000_000))
  }

  func testTwoCodexWindowsUseLabelsAndIgnoreLegacyOtherLimit() throws {
    let snapshot = try decode(
      """
      {"result":{"rateLimits":{"limitId":"other","primary":{"usedPercent":0,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":34,"windowDurationMins":300},"secondary":{"usedPercent":37,"windowDurationMins":10080}}}}}
      """)

    XCTAssertEqual(UsageMenuFormatter.title(for: .success(snapshot)), "5h 66% 7d 63%")
  }

  func testLegacyCodexLimitWorks() throws {
    let snapshot = try decode(
      """
      {"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":35.5,"windowDurationMins":300}}}}
      """)
    XCTAssertEqual(UsageMenuFormatter.title(for: .success(snapshot)), "65%")
  }

  func testNeverSubstitutesAnotherLimitID() {
    XCTAssertThrowsError(
      try decode(
        """
        {"result":{"rateLimitsByLimitId":{"codex_other":{"primary":{"usedPercent":10,"windowDurationMins":300}}}}}
        """)
    ) { error in
      XCTAssertEqual(error as? CodexUsageError, .noQuota)
    }
    XCTAssertThrowsError(
      try decode(
        """
        {"result":{"rateLimitsByLimitId":{"codex":{},"codex_other":{"primary":{"usedPercent":10,"windowDurationMins":300}}}}}
        """)
    ) { error in
      XCTAssertEqual(error as? CodexUsageError, .noQuota)
    }
  }

  func testMalformedServerErrorAndMissingUsage() {
    XCTAssertThrowsError(try decode("not json")) {
      XCTAssertEqual($0 as? CodexUsageError, .invalidResponse)
    }
    XCTAssertThrowsError(try decode(#"{"error":{"code":-32000,"message":"secret"}}"#)) {
      XCTAssertEqual($0 as? CodexUsageError, .serverRejected)
    }
    XCTAssertThrowsError(try decode(#"{"result":{"rateLimits":{"primary":{}}}}"#)) {
      XCTAssertEqual($0 as? CodexUsageError, .noQuota)
    }
  }

  func testOutOfRangeUsageIsClamped() throws {
    let snapshot = try decode(
      """
      {"result":{"rateLimits":{"primary":{"usedPercent":-10,"windowDurationMins":300},"secondary":{"usedPercent":150,"windowDurationMins":10080}}}}
      """)
    XCTAssertEqual(UsageMenuFormatter.title(for: .success(snapshot)), "5h 100% 7d 0%")
  }

  func testUnknownWindowIsPreservedAlongsideKnownWindow() throws {
    let snapshot = try decode(
      """
      {"result":{"rateLimits":{"primary":{"windowDurationMins":300},"secondary":{"usedPercent":37,"windowDurationMins":10080}}}}
      """)
    XCTAssertEqual(snapshot.quotaWindows.count, 2)
    XCTAssertNil(snapshot.quotaWindows.first?.remainingPercent)
    XCTAssertEqual(UsageMenuFormatter.title(for: .success(snapshot)), "5h -- 7d 63%")
  }

  func testCodexBinaryOverrideDoesNotFallBack() {
    let environment = ["CODEX_BIN": "/does/not/exist", "PATH": "/usr/bin"]
    XCTAssertNil(CodexBinaryLocator.resolve(environment: environment, home: "/tmp"))
    XCTAssertEqual(
      CodexBinaryLocator.candidates(environment: environment, home: "/tmp"), ["/does/not/exist"])
    XCTAssertThrowsError(
      try CodexBinaryLocator.resolveForLaunch(environment: environment, home: "/tmp")
    ) {
      XCTAssertEqual($0 as? CodexUsageError, .invalidBinaryOverride)
    }
  }

  func testChatGPTBundlePathIsSearchedWithoutShellPath() {
    let paths = CodexBinaryLocator.candidates(environment: [:], home: "/tmp/test-user")
    XCTAssertTrue(
      paths.contains(
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"))
  }

  func testProviderMapsTransportAndDecoderErrors() async throws {
    let good = Data(
      #"{"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300}}}}"#.utf8)
    let provider = CodexProvider(appServer: StubAppServer(result: .success(good)))
    let snapshot = try await provider.fetch()
    XCTAssertEqual(UsageMenuFormatter.title(for: .success(snapshot)), "75%")

    let failed = CodexProvider(appServer: StubAppServer(result: .failure(.timeout)))
    do {
      _ = try await failed.fetch()
      XCTFail("Expected timeout")
    } catch {
      XCTAssertEqual(error as? CodexUsageError, .timeout)
    }
  }

  private func decode(_ json: String) throws -> UsageSnapshot {
    try CodexRateLimitDecoder.decode(Data(json.utf8), fetchedAt: Date(timeIntervalSince1970: 100))
  }
}

@MainActor
final class UsageControllerTests: XCTestCase {
  func testTestHostDoesNotStartLiveCodexRefresh() {
    let environment = ProcessInfo.processInfo.environment
    XCTAssertEqual(environment["PULSE_DISABLE_LIVE_USAGE"], "1")
    XCTAssertFalse(PulseAppDelegate.shouldStartLiveUsage(environment: environment))
    XCTAssertTrue(PulseAppDelegate.shouldStartLiveUsage(environment: [:]))
  }

  func testRefreshTransitionsFromSuccessToErrorWithoutStaleNumber() async {
    let snapshot = UsageSnapshot(
      providerID: "codex",
      fetchedAt: Date(timeIntervalSince1970: 100),
      metrics: [.quota(QuotaWindow(durationMinutes: 300, remainingPercent: 75, resetsAt: nil))]
    )
    let provider = QueueUsageProvider(results: [
      .success(snapshot), .failure(CodexUsageError.timeout),
    ])
    let controller = UsageController(provider: provider)

    XCTAssertEqual(controller.state, .loading)
    await controller.refresh()
    XCTAssertEqual(controller.state, .success(snapshot))
    await controller.refresh()
    if case .failure(let message) = controller.state {
      XCTAssertTrue(message.contains("did not respond"))
    } else {
      XCTFail("Expected error state")
    }
    XCTAssertEqual(UsageMenuFormatter.title(for: controller.state), "!")
  }

  func testMissingQuotaBecomesUnavailable() async {
    let snapshot = UsageSnapshot(providerID: "codex", fetchedAt: Date(), metrics: [])
    let controller = UsageController(provider: QueueUsageProvider(results: [.success(snapshot)]))
    await controller.refresh()
    if case .unavailable = controller.state {} else { XCTFail("Expected unavailable state") }
    XCTAssertEqual(UsageMenuFormatter.title(for: controller.state), "--")
  }

  func testNonQuotaMetricRemainsAvailableToFutureProviders() async {
    let snapshot = UsageSnapshot(
      providerID: "future-provider",
      fetchedAt: Date(),
      metrics: [.balance(amount: 10, currency: "USD")]
    )
    let controller = UsageController(provider: QueueUsageProvider(results: [.success(snapshot)]))
    await controller.refresh()
    XCTAssertEqual(controller.state, .success(snapshot))
  }

  func testBackgroundRefreshKeepsCurrentQuotaVisible() async {
    let snapshot = UsageSnapshot(
      providerID: "codex",
      fetchedAt: Date(timeIntervalSince1970: 100),
      metrics: [.quota(QuotaWindow(durationMinutes: 300, remainingPercent: 75, resetsAt: nil))]
    )
    let provider = PausedUsageProvider(snapshot: snapshot)
    let controller = UsageController(provider: provider)

    await controller.refresh()
    let secondRefresh = Task { await controller.refresh() }
    await provider.waitForSecondFetch()

    XCTAssertTrue(controller.isRefreshing)
    XCTAssertEqual(controller.state, .success(snapshot))
    XCTAssertEqual(UsageMenuFormatter.title(for: controller.state), "75%")

    await provider.completeSecondFetch()
    await secondRefresh.value
    XCTAssertFalse(controller.isRefreshing)
  }

  func testStaleRefreshSkipsRecentSnapshotAndRefreshesAnOldOne() async {
    let recent = UsageSnapshot(
      providerID: "88vip",
      fetchedAt: Date(),
      metrics: [.balance(amount: 1, currency: "USD")]
    )
    let old = UsageSnapshot(
      providerID: "88vip",
      fetchedAt: Date(timeIntervalSince1970: 0),
      metrics: [.balance(amount: 2, currency: "USD")]
    )
    let recentProvider = QueueUsageProvider(results: [.success(recent), .success(old)])
    let recentController = UsageController(provider: recentProvider)
    await recentController.refresh()
    XCTAssertNil(recentController.refreshIfStale(maxAge: 600))
    XCTAssertEqual(recentController.state, .success(recent))

    let oldProvider = QueueUsageProvider(results: [.success(old), .success(recent)])
    let oldController = UsageController(provider: oldProvider)
    await oldController.refresh()
    let refreshTask = oldController.refreshIfStale(maxAge: 600)
    XCTAssertNotNil(refreshTask)
    await refreshTask?.value
    XCTAssertEqual(oldController.state, .success(recent))
  }
}

private struct StubAppServer: CodexAppServerReading {
  let result: Result<Data, CodexUsageError>

  func readRateLimits() async throws -> Data { try result.get() }
}

private actor QueueUsageProvider: UsageProviding {
  private var results: [Result<UsageSnapshot, CodexUsageError>]

  init(results: [Result<UsageSnapshot, CodexUsageError>]) { self.results = results }

  func fetch() async throws -> UsageSnapshot {
    guard !results.isEmpty else { throw CodexUsageError.noQuota }
    return try results.removeFirst().get()
  }
}

private actor PausedUsageProvider: UsageProviding {
  private let snapshot: UsageSnapshot
  private var fetchCount = 0
  private var secondStarted = false
  private var secondStartWaiter: CheckedContinuation<Void, Never>?
  private var secondFetchWaiter: CheckedContinuation<UsageSnapshot, Never>?

  init(snapshot: UsageSnapshot) { self.snapshot = snapshot }

  func fetch() async throws -> UsageSnapshot {
    fetchCount += 1
    guard fetchCount > 1 else { return snapshot }
    secondStarted = true
    secondStartWaiter?.resume()
    secondStartWaiter = nil
    return await withCheckedContinuation { secondFetchWaiter = $0 }
  }

  func waitForSecondFetch() async {
    if secondStarted { return }
    await withCheckedContinuation { secondStartWaiter = $0 }
  }

  func completeSecondFetch() {
    secondFetchWaiter?.resume(returning: snapshot)
    secondFetchWaiter = nil
  }
}
