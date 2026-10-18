import Combine
import Foundation
import XCTest

@testable import Pulse

final class DeepSeekUsageTests: XCTestCase {
  func testOfficialRequestAndNativeBalancesPreserveDecimals() async throws {
    let store = DeepSeekMemorySecrets()
    try store.save("  synthetic-key  ", account: DeepSeekConfiguration.keychainAccount)
    let client = DeepSeekTestHTTPClient(
      body: Self.body(
        #"{"currency":"USD","total_balance":"2.3456789"},{"currency":"CNY","total_balance":"42.68"}"#
      ))
    let snapshot = try await DeepSeekProvider(secretStore: store, httpClient: client).fetch()
    XCTAssertEqual(snapshot.providerID, "deepseek")
    XCTAssertEqual(
      snapshot.metrics,
      [
        .balance(amount: Decimal(string: "2.3456789")!, currency: "USD"),
        .balance(amount: Decimal(string: "42.68")!, currency: "CNY"),
      ])
    XCTAssertEqual(DeepSeekUsageFormatter.title(for: .success(snapshot)), "¥42.68")
    XCTAssertTrue(snapshot.quotaWindows.isEmpty)
    let capturedRequest = await client.lastRequest()
    let request = try XCTUnwrap(capturedRequest)
    XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/user/balance")
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(request.timeoutInterval, 20)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-key")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
  }

  func testZeroNegativeAndUnavailableFundingAreStillBalances() throws {
    for value in ["0", "-0.25", "12345678.12345678"] {
      let snapshot = try DeepSeekUsageDecoder.decode(
        Data(
          Self.body(
            "{\"currency\":\"USD\",\"total_balance\":\"\(value)\"}", available: false
          ).utf8))
      XCTAssertEqual(snapshot.metrics, [.balance(amount: Decimal(string: value)!, currency: "USD")])
      XCTAssertNotEqual(DeepSeekUsageFormatter.title(for: .success(snapshot)), "!")
    }
  }

  func testMalformedEmptyAndDuplicateDataNeverInventBalances() {
    let invalid = [
      "not json", "{}", Self.body(""),
      Self.body(#"{"currency":"CNY"}"#),
      Self.body(#"{"currency":"EUR","total_balance":"12.34"}"#),
      Self.body(#"{"currency":"CNY","total_balance":12.34}"#),
      Self.body(#"{"currency":"CNY","total_balance":null}"#),
      Self.body(#"{"currency":"CNY","total_balance":"1"},{"currency":"CNY","total_balance":"2"}"#),
      #"{"is_available":"true","balance_infos":[]}"#,
    ]
    for body in invalid {
      XCTAssertThrowsError(try DeepSeekUsageDecoder.decode(Data(body.utf8))) {
        XCTAssertEqual($0 as? DeepSeekUsageError, .invalidResponse)
      }
    }
    for amount in [
      "", "NaN", "Infinity", "12.34junk", " 12.34", "12.34\n", "1,234", "1e9999", "--1",
    ] {
      let json = try! JSONSerialization.data(withJSONObject: [
        "is_available": true,
        "balance_infos": [["currency": "USD", "total_balance": amount]],
      ])
      XCTAssertThrowsError(try DeepSeekUsageDecoder.decode(json))
    }
  }

  func testHTTPFailuresAreClassifiedWithoutResponseBody() async {
    for (status, expected) in [
      (401, DeepSeekUsageError.invalidCredentials), (403, .invalidCredentials),
      (404, .endpointUnavailable), (405, .endpointUnavailable), (429, .rateLimited),
      (500, .serviceStatus(500)),
    ] {
      let store = DeepSeekMemorySecrets()
      try! store.save("synthetic-key", account: DeepSeekConfiguration.keychainAccount)
      let provider = DeepSeekProvider(
        secretStore: store, httpClient: DeepSeekTestHTTPClient(body: "private-body", status: status)
      )
      do {
        _ = try await provider.fetch()
        XCTFail("Expected HTTP \(status) failure")
      } catch {
        XCTAssertEqual(error as? DeepSeekUsageError, expected)
        XCTAssertFalse(String(describing: error).contains("private-body"))
      }
    }
  }

  func testMissingAndUnreadableKeysDoNotSendRequests() async {
    for value in [nil, "   "] as [String?] {
      let store = DeepSeekMemorySecrets()
      if let value { try! store.save(value, account: DeepSeekConfiguration.keychainAccount) }
      let client = DeepSeekTestHTTPClient(body: "{}")
      await expect(
        .missingAPIKey, provider: DeepSeekProvider(secretStore: store, httpClient: client))
      let request = await client.lastRequest()
      XCTAssertNil(request)
    }
    let store = DeepSeekMemorySecrets()
    store.failure = .invalidStoredValue
    await expect(
      .keychainUnavailable,
      provider: DeepSeekProvider(
        secretStore: store, httpClient: DeepSeekTestHTTPClient(body: "{}")))
  }

  func testNetworkTimeoutAndCancellationStayDistinct() async {
    for (code, expected) in [
      (URLError.Code.notConnectedToInternet, DeepSeekUsageError.networkUnavailable),
      (.timedOut, .timedOut),
    ] {
      let store = DeepSeekMemorySecrets()
      try! store.save("synthetic-key", account: DeepSeekConfiguration.keychainAccount)
      await expect(
        expected,
        provider: DeepSeekProvider(
          secretStore: store, httpClient: DeepSeekTestHTTPClient(error: URLError(code))))
    }
    for error in [CancellationError(), URLError(.cancelled)] as [any Error] {
      let store = DeepSeekMemorySecrets()
      try! store.save("synthetic-key", account: DeepSeekConfiguration.keychainAccount)
      do {
        _ = try await DeepSeekProvider(
          secretStore: store, httpClient: DeepSeekTestHTTPClient(error: error)
        ).fetch()
        XCTFail("Expected cancellation")
      } catch {
        XCTAssertTrue(error is CancellationError)
      }
    }
  }

  @MainActor
  func testSaveReplaceRemoveAreIsolatedFromVIP() throws {
    let store = DeepSeekMemorySecrets()
    let vip = VIPConfiguration(secretStore: store)
    let deepSeek = DeepSeekConfiguration(secretStore: store)
    XCTAssertTrue(vip.save(apiKey: "vip-synthetic"))
    XCTAssertFalse(deepSeek.save(apiKey: "   "))
    XCTAssertTrue(deepSeek.save(apiKey: "  deepseek-synthetic  "))
    XCTAssertEqual(
      try store.read(account: DeepSeekConfiguration.keychainAccount), "deepseek-synthetic")
    XCTAssertTrue(deepSeek.save(apiKey: "replacement-synthetic"))
    deepSeek.refresh()
    XCTAssertTrue(deepSeek.hasAPIKey)
    XCTAssertTrue(deepSeek.removeAPIKey())
    XCTAssertFalse(deepSeek.hasAPIKey)
    XCTAssertNil(try store.read(account: DeepSeekConfiguration.keychainAccount))
    XCTAssertEqual(try store.read(account: VIPConfiguration.keychainAccount), "vip-synthetic")
    XCTAssertEqual(VIPConfiguration.keychainAccount, "88VIP API key")
  }

  @MainActor
  func testConfigurationStorageFailuresPreserveKnownCredentialState() {
    let store = DeepSeekMemorySecrets()
    let configuration = DeepSeekConfiguration(secretStore: store)
    store.failure = .invalidStoredValue
    configuration.refresh()
    XCTAssertFalse(configuration.hasAPIKey)
    XCTAssertTrue(configuration.errorMessage?.contains("Keychain") == true)
    XCTAssertFalse(configuration.save(apiKey: "synthetic-key"))
    store.failure = nil
    XCTAssertTrue(configuration.save(apiKey: "synthetic-key"))
    store.failure = .invalidStoredValue
    XCTAssertFalse(configuration.removeAPIKey())
    XCTAssertTrue(configuration.hasAPIKey)
    XCTAssertTrue(configuration.errorMessage?.contains("Keychain") == true)
  }

  func testCompactStatesUseNativeCurrencyAndNeverOldMoney() throws {
    XCTAssertEqual(DeepSeekUsageFormatter.title(for: .loading), "…")
    XCTAssertEqual(DeepSeekUsageFormatter.title(for: .unavailable("Setup")), "!")
    XCTAssertEqual(DeepSeekUsageFormatter.title(for: .failure("Retry")), "!")
    let snapshot = try DeepSeekUsageDecoder.decode(
      Data(
        Self.body(
          #"{"currency":"USD","total_balance":"104.22"}"#
        ).utf8))
    XCTAssertEqual(DeepSeekUsageFormatter.title(for: .success(snapshot)), "$104.22")
  }

  @MainActor
  func testCancellationBeforeFetchReleasesSingleFlightGuard() async {
    let expected = Self.snapshot(42.68)
    let controller = UsageController(provider: ImmediateBalanceProvider(snapshot: expected))
    var refreshTask: Task<Void, Never>?
    let subscription = controller.$isRefreshing.dropFirst().sink { refreshing in
      if refreshing { refreshTask?.cancel() }
    }
    refreshTask = controller.requestRefresh()
    await refreshTask?.value
    XCTAssertFalse(controller.isRefreshing)
    subscription.cancel()
    await controller.refresh()
    XCTAssertEqual(controller.state, .success(expected))
  }

  @MainActor
  func testReplaceWhileFetchingStartsFreshRequestAndRejectsLateOldReply() async {
    let provider = SuspendedBalanceProvider()
    let controller = UsageController(provider: provider)
    let oldRefresh = controller.requestRefresh()
    await provider.waitForRequests(1)
    let replacement = controller.credentialsDidChange()
    XCTAssertEqual(controller.state, .loading)
    await provider.waitForRequests(2)
    await provider.complete(1, result: .success(Self.snapshot(42.68)))
    await replacement.value
    XCTAssertEqual(controller.state, .success(Self.snapshot(42.68)))
    await provider.complete(0, result: .success(Self.snapshot(999)))
    await oldRefresh.value
    XCTAssertEqual(controller.state, .success(Self.snapshot(42.68)))
    XCTAssertFalse(controller.isRefreshing)
  }

  @MainActor
  func testRemoveClearsSuccessfulMoneyAndLateRequestCannotRestoreIt() async {
    let provider = SuspendedBalanceProvider()
    let controller = UsageController(provider: provider)
    let initial = controller.requestRefresh()
    await provider.waitForRequests(1)
    await provider.complete(0, result: .success(Self.snapshot(100)))
    await initial.value
    let inFlight = controller.requestRefresh()
    await provider.waitForRequests(2)
    let removed = controller.credentialsDidChange()
    XCTAssertEqual(controller.state, .loading)
    await provider.waitForRequests(3)
    await provider.complete(2, result: .failure(DeepSeekUsageError.missingAPIKey))
    await removed.value
    XCTAssertEqual(controller.state, .unavailable(DeepSeekUsageError.missingAPIKey.userMessage))
    await provider.complete(1, result: .success(Self.snapshot(99)))
    await inFlight.value
    XCTAssertEqual(controller.state, .unavailable(DeepSeekUsageError.missingAPIKey.userMessage))
  }

  private func expect(_ expected: DeepSeekUsageError, provider: DeepSeekProvider) async {
    do {
      _ = try await provider.fetch()
      XCTFail("Expected \(expected)")
    } catch { XCTAssertEqual(error as? DeepSeekUsageError, expected) }
  }

  private static func body(_ entries: String, available: Bool = true) -> String {
    "{\"is_available\":\(available),\"balance_infos\":[\(entries)]}"
  }

  private static func snapshot(_ balance: Decimal) -> UsageSnapshot {
    UsageSnapshot(
      providerID: "deepseek", fetchedAt: Date(timeIntervalSince1970: 100),
      metrics: [.balance(amount: balance, currency: "CNY")])
  }
}

private final class DeepSeekMemorySecrets: SecretStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String] = [:]
  var failure: SecretStoreError?

  func read(account: String) throws -> String? {
    try lock.withLock {
      if let failure { throw failure }
      return values[account]
    }
  }
  func save(_ secret: String, account: String) throws {
    try lock.withLock {
      if let failure { throw failure }
      values[account] = secret
    }
  }
  func delete(account: String) throws {
    try lock.withLock {
      if let failure { throw failure }
      values[account] = nil
    }
  }
}

private actor DeepSeekTestHTTPClient: DeepSeekHTTPClient {
  let body: String
  let status: Int
  let error: (any Error)?
  private var request: URLRequest?
  init(body: String = "{}", status: Int = 200, error: (any Error)? = nil) {
    self.body = body
    self.status = status
    self.error = error
  }
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    self.request = request
    if let error { throw error }
    return (
      Data(body.utf8),
      HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    )
  }
  func lastRequest() -> URLRequest? { request }
}

/// Deliberately ignores cancellation so generation rejection is exercised.
private actor SuspendedBalanceProvider: UsageProviding {
  private var continuations: [CheckedContinuation<UsageSnapshot, any Error>] = []
  func fetch() async throws -> UsageSnapshot {
    try await withCheckedThrowingContinuation { continuations.append($0) }
  }
  func waitForRequests(_ count: Int) async {
    while continuations.count < count { await Task.yield() }
  }
  func complete(_ index: Int, result: Result<UsageSnapshot, any Error>) {
    continuations[index].resume(with: result)
  }
}

private struct ImmediateBalanceProvider: UsageProviding {
  let snapshot: UsageSnapshot
  func fetch() async throws -> UsageSnapshot { snapshot }
}
