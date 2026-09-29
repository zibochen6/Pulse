import Foundation

enum VIPUsageError: LocalizedError, Equatable, UsageFailureDescribing {
  case missingAPIKey
  case keychainUnavailable
  case invalidCredentials
  case rateLimited
  case billingUnavailable
  case serviceStatus(Int)
  case networkUnavailable
  case invalidResponse

  var isUnavailable: Bool {
    switch self {
    case .missingAPIKey, .billingUnavailable:
      true
    default:
      false
    }
  }

  var userMessage: String { errorDescription ?? "Could not refresh 88VIP balance." }

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      "Add an 88VIP API key in Settings to view its balance."
    case .keychainUnavailable:
      "Pulse could not read the 88VIP API key from Keychain."
    case .invalidCredentials:
      "The 88VIP API key is invalid or no longer active."
    case .rateLimited:
      "88VIP is rate-limiting balance requests. Try again later."
    case .billingUnavailable:
      "88VIP does not currently provide a compatible billing endpoint."
    case .serviceStatus(let status):
      "88VIP's billing service returned HTTP \(status)."
    case .networkUnavailable:
      "Could not reach 88VIP. Check your network and try again."
    case .invalidResponse:
      "88VIP returned balance data Pulse could not read."
    }
  }
}

protocol VIPHTTPClient: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionVIPHTTPClient: VIPHTTPClient {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw VIPUsageError.networkUnavailable
      }
      return (data, httpResponse)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as VIPUsageError {
      throw error
    } catch {
      throw VIPUsageError.networkUnavailable
    }
  }
}

struct VIPProvider: UsageProviding {
  static let providerID = "88vip"
  static let baseURL = URL(string: "https://88api.ai/v1")!

  private let secretStore: any SecretStoring
  private let httpClient: any VIPHTTPClient

  init(
    secretStore: any SecretStoring = KeychainSecretStore(),
    httpClient: any VIPHTTPClient = URLSessionVIPHTTPClient()
  ) {
    self.secretStore = secretStore
    self.httpClient = httpClient
  }

  func fetch() async throws -> UsageSnapshot {
    let apiKey: String
    do {
      guard let savedKey = try secretStore.read(account: VIPConfiguration.keychainAccount)
      else {
        throw VIPUsageError.missingAPIKey
      }
      let trimmedKey = savedKey.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedKey.isEmpty else { throw VIPUsageError.missingAPIKey }
      apiKey = trimmedKey
    } catch let error as VIPUsageError {
      throw error
    } catch {
      throw VIPUsageError.keychainUnavailable
    }

    let subscriptionData = try await request(path: "dashboard/billing/subscription", apiKey: apiKey)
    let subscription = try VIPUsageDecoder.decodeSubscription(subscriptionData)
    let fetchedAt = Date()

    guard let allowance = subscription.allowance else {
      var metrics: [UsageMetric] = [.unlimited]
      if let expiry = subscription.accessExpiry { metrics.append(.expiresAt(expiry)) }
      return UsageSnapshot(providerID: Self.providerID, fetchedAt: fetchedAt, metrics: metrics)
    }

    var metrics: [UsageMetric] = [.allowance(amount: allowance, currency: "USD")]
    if let expiry = subscription.accessExpiry { metrics.append(.expiresAt(expiry)) }

    do {
      let usageData = try await request(path: "dashboard/billing/usage", apiKey: apiKey)
      let used = try VIPUsageDecoder.decodeUsage(usageData)
      metrics.append(.usage(amount: used, currency: "USD"))
      metrics.append(.balance(amount: max(0, allowance - used), currency: "USD"))
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as VIPUsageError {
      metrics.append(.unavailable(reason: error.userMessage))
    } catch {
      metrics.append(.unavailable(reason: VIPUsageError.networkUnavailable.userMessage))
    }

    return UsageSnapshot(providerID: Self.providerID, fetchedAt: fetchedAt, metrics: metrics)
  }

  private func request(path: String, apiKey: String) async throws -> Data {
    let url = Self.baseURL.appending(path: path)
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await httpClient.data(for: request)
    switch response.statusCode {
    case 200..<300:
      return data
    case 401, 403:
      throw VIPUsageError.invalidCredentials
    case 404, 405:
      throw VIPUsageError.billingUnavailable
    case 429:
      throw VIPUsageError.rateLimited
    default:
      throw VIPUsageError.serviceStatus(response.statusCode)
    }
  }
}

enum VIPUsageDecoder {
  static func decodeSubscription(_ data: Data) throws -> VIPSubscription {
    do {
      return try JSONDecoder().decode(VIPSubscription.self, from: data)
    } catch {
      throw VIPUsageError.invalidResponse
    }
  }

  static func decodeUsage(_ data: Data) throws -> Decimal {
    do {
      let response = try JSONDecoder().decode(VIPUsage.self, from: data)
      guard let cents = response.totalUsage, cents >= 0 else { throw VIPUsageError.invalidResponse }
      return cents / 100
    } catch let error as VIPUsageError {
      throw error
    } catch {
      throw VIPUsageError.invalidResponse
    }
  }
}

struct VIPSubscription: Decodable {
  let hardLimit: Decimal?
  let softLimit: Decimal?
  let systemHardLimit: Decimal?
  let accessExpiryTimestamp: Decimal?

  var allowance: Decimal? {
    [hardLimit, softLimit, systemHardLimit].compactMap { $0 }.first { $0 > 0 }
  }

  var accessExpiry: Date? {
    guard let accessExpiryTimestamp, accessExpiryTimestamp > 0 else { return nil }
    return Date(timeIntervalSince1970: NSDecimalNumber(decimal: accessExpiryTimestamp).doubleValue)
  }

  private enum CodingKeys: String, CodingKey {
    case hardLimit = "hard_limit_usd"
    case softLimit = "soft_limit_usd"
    case systemHardLimit = "system_hard_limit_usd"
    case accessExpiryTimestamp = "access_until"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hardLimit = try container.lossyDecimal(forKey: .hardLimit)
    softLimit = try container.lossyDecimal(forKey: .softLimit)
    systemHardLimit = try container.lossyDecimal(forKey: .systemHardLimit)
    accessExpiryTimestamp = try container.lossyDecimal(forKey: .accessExpiryTimestamp)
  }
}

private struct VIPUsage: Decodable {
  let totalUsage: Decimal?

  private enum CodingKeys: String, CodingKey {
    case totalUsage = "total_usage"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    totalUsage = try container.lossyDecimal(forKey: .totalUsage)
  }
}

private extension KeyedDecodingContainer {
  func lossyDecimal(forKey key: Key) throws -> Decimal? {
    guard contains(key), try !decodeNil(forKey: key) else { return nil }
    if let decimal = try? decode(Decimal.self, forKey: key) { return decimal }
    if let string = try? decode(String.self, forKey: key),
      let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
    {
      return decimal
    }
    throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected a number")
  }
}
