import Foundation
import XCTest

@testable import Pulse

final class VIPUsageTests: XCTestCase {
  func testProviderCalculatesUSDRemainingFromCents() async throws {
    let store = MemorySecretStore(value: "test-key")
    let client = QueueVIPHTTPClient(responses: [
      .success(response("""
        {"hard_limit_usd":100,"soft_limit_usd":90,"access_until":1780000000}
        """)),
      .success(response("""
        {"total_usage":1234}
        """)),
    ])
    let snapshot = try await VIPProvider(secretStore: store, httpClient: client).fetch()

    XCTAssertEqual(snapshot.providerID, VIPProvider.providerID)
    XCTAssertEqual(amount(.allowance, in: snapshot), 100)
    XCTAssertEqual(amount(.usage, in: snapshot), 12.34)
    XCTAssertEqual(amount(.balance, in: snapshot), 87.66)
    XCTAssertEqual(VIPUsageFormatter.title(for: .success(snapshot)), "$87.66")
    XCTAssertEqual(expiry(in: snapshot), Date(timeIntervalSince1970: 1_780_000_000))
  }

  func testProviderUsesFallbackLimitAndDoesNotInventMissingRemaining() async throws {
    let store = MemorySecretStore(value: "test-key")
    let client = QueueVIPHTTPClient(responses: [
      .success(response(#"{"hard_limit_usd":0,"soft_limit_usd":"25"}"#)),
      .failure(VIPUsageError.rateLimited),
    ])
    let snapshot = try await VIPProvider(secretStore: store, httpClient: client).fetch()

    XCTAssertEqual(amount(.allowance, in: snapshot), 25)
    XCTAssertNil(amount(.balance, in: snapshot))
    XCTAssertEqual(VIPUsageFormatter.title(for: .success(snapshot)), "--")
    XCTAssertTrue(unavailableMessages(in: snapshot).contains { $0.contains("rate-limiting") })
  }

  func testProviderReportsUnlimitedWithoutFabricatingMoney() async throws {
    let store = MemorySecretStore(value: "test-key")
    let client = QueueVIPHTTPClient(responses: [.success(response("{}"))])
    let snapshot = try await VIPProvider(secretStore: store, httpClient: client).fetch()

    XCTAssertEqual(snapshot.metrics, [.unlimited])
    XCTAssertEqual(VIPUsageFormatter.title(for: .success(snapshot)), "∞")
  }

  func testMissingKeyAndHTTPFailuresAreClassified() async throws {
    let noKeyProvider = VIPProvider(secretStore: MemorySecretStore(), httpClient: QueueVIPHTTPClient(responses: []))
    await XCTAssertThrowsErrorAsync(try await noKeyProvider.fetch()) { error in
      XCTAssertEqual(error as? VIPUsageError, .missingAPIKey)
    }

    let whitespaceKeyProvider = VIPProvider(
      secretStore: MemorySecretStore(value: "   "),
      httpClient: QueueVIPHTTPClient(responses: [])
    )
    await XCTAssertThrowsErrorAsync(try await whitespaceKeyProvider.fetch()) { error in
      XCTAssertEqual(error as? VIPUsageError, .missingAPIKey)
    }

    let invalidKeyProvider = VIPProvider(
      secretStore: MemorySecretStore(value: "test-key"),
      httpClient: QueueVIPHTTPClient(responses: [.success(response("{}", status: 401))])
    )
    await XCTAssertThrowsErrorAsync(try await invalidKeyProvider.fetch()) { error in
      XCTAssertEqual(error as? VIPUsageError, .invalidCredentials)
    }

    let malformedProvider = VIPProvider(
      secretStore: MemorySecretStore(value: "test-key"),
      httpClient: QueueVIPHTTPClient(responses: [.success(response("not json"))])
    )
    await XCTAssertThrowsErrorAsync(try await malformedProvider.fetch()) { error in
      XCTAssertEqual(error as? VIPUsageError, .invalidResponse)
    }

    let endpointProvider = VIPProvider(
      secretStore: MemorySecretStore(value: "test-key"),
      httpClient: QueueVIPHTTPClient(responses: [.success(response("{}", status: 404))])
    )
    await XCTAssertThrowsErrorAsync(try await endpointProvider.fetch()) { error in
      XCTAssertEqual(error as? VIPUsageError, .billingUnavailable)
    }

    let networkProvider = VIPProvider(
      secretStore: MemorySecretStore(value: "test-key"),
      httpClient: QueueVIPHTTPClient(responses: [.failure(VIPUsageError.networkUnavailable)])
    )
    await XCTAssertThrowsErrorAsync(try await networkProvider.fetch()) { error in
      XCTAssertEqual(error as? VIPUsageError, .networkUnavailable)
    }
  }

  @MainActor
  func testConfigurationSavesReplacesAndRemovesOnlyThroughSecretStore() {
    let store = MemorySecretStore()
    let configuration = VIPConfiguration(secretStore: store)

    XCTAssertFalse(configuration.hasAPIKey)
    XCTAssertFalse(configuration.save(apiKey: "   "))
    XCTAssertNotNil(configuration.errorMessage)

    XCTAssertTrue(configuration.save(apiKey: "  test-key  "))
    XCTAssertTrue(configuration.hasAPIKey)
    XCTAssertEqual(store.value, "test-key")

    configuration.refresh()
    XCTAssertTrue(configuration.hasAPIKey)
    XCTAssertTrue(configuration.removeAPIKey())
    XCTAssertFalse(configuration.hasAPIKey)
    XCTAssertNil(store.value)
  }

  @MainActor
  func testConfigurationShowsKeychainFailureWithoutPersistingAKey() {
    let store = MemorySecretStore(saveError: SecretStoreError.unexpectedStatus(-1))
    let configuration = VIPConfiguration(secretStore: store)

    XCTAssertFalse(configuration.save(apiKey: "test-key"))
    XCTAssertFalse(configuration.hasAPIKey)
    XCTAssertNotNil(configuration.errorMessage)
    XCTAssertNil(store.value)
  }

  @MainActor
  func testConfigurationTreatsAnEmptyStoredKeyAsNotConnected() {
    let configuration = VIPConfiguration(secretStore: MemorySecretStore(value: "  "))

    configuration.refresh()

    XCTAssertFalse(configuration.hasAPIKey)
  }

  private func response(_ body: String, status: Int = 200) -> (Data, HTTPURLResponse) {
    let url = URL(string: "https://88api.ai/v1/dashboard/billing/subscription")!
    return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
  }

  private enum AmountKind {
    case allowance
    case usage
    case balance
  }

  private func amount(_ kind: AmountKind, in snapshot: UsageSnapshot) -> Decimal? {
    for metric in snapshot.metrics {
      switch (kind, metric) {
      case (.allowance, .allowance(let amount, _)),
        (.usage, .usage(let amount, _)),
        (.balance, .balance(let amount, _)):
        return amount
      default:
        continue
      }
    }
    return nil
  }

  private func expiry(in snapshot: UsageSnapshot) -> Date? {
    for metric in snapshot.metrics {
      if case .expiresAt(let date) = metric { return date }
    }
    return nil
  }

  private func unavailableMessages(in snapshot: UsageSnapshot) -> [String] {
    snapshot.metrics.compactMap {
      guard case .unavailable(let message) = $0 else { return nil }
      return message
    }
  }
}

private final class MemorySecretStore: SecretStoring, @unchecked Sendable {
  var value: String?
  var saveError: Error?

  init(value: String? = nil, saveError: Error? = nil) {
    self.value = value
    self.saveError = saveError
  }

  func read(account: String) throws -> String? { value }

  func save(_ secret: String, account: String) throws {
    if let saveError { throw saveError }
    value = secret
  }

  func delete(account: String) throws { value = nil }
}

private actor QueueVIPHTTPClient: VIPHTTPClient {
  private var responses: [Result<(Data, HTTPURLResponse), Error>]

  init(responses: [Result<(Data, HTTPURLResponse), Error>]) {
    self.responses = responses
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    guard !responses.isEmpty else { throw VIPUsageError.networkUnavailable }
    return try responses.removeFirst().get()
  }
}

private func XCTAssertThrowsErrorAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  _ errorHandler: (Error) -> Void
) async {
  do {
    _ = try await expression()
    XCTFail("Expected an error")
  } catch {
    errorHandler(error)
  }
}
