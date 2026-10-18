import Foundation

protocol DeepSeekHTTPClient: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionDeepSeekHTTPClient: DeepSeekHTTPClient {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw DeepSeekUsageError.networkUnavailable
    }
    return (data, response)
  }
}

enum DeepSeekUsageError: LocalizedError, Equatable, UsageFailureDescribing {
  case missingAPIKey
  case keychainUnavailable
  case invalidCredentials
  case rateLimited
  case endpointUnavailable
  case serviceStatus(Int)
  case networkUnavailable
  case timedOut
  case invalidResponse

  var isUnavailable: Bool {
    switch self {
    case .missingAPIKey, .endpointUnavailable: true
    default: false
    }
  }

  var userMessage: String { errorDescription ?? "Could not refresh DeepSeek balance." }

  var errorDescription: String? {
    switch self {
    case .missingAPIKey: "Add a DeepSeek API key in Settings → Providers to view its balance."
    case .keychainUnavailable: "Pulse could not read the DeepSeek API key from Keychain."
    case .invalidCredentials: "The DeepSeek API key is invalid or no longer active."
    case .rateLimited: "DeepSeek is rate-limiting balance requests. Try again later."
    case .endpointUnavailable: "DeepSeek's balance endpoint is currently unavailable."
    case .serviceStatus(let status): "DeepSeek's balance service returned HTTP \(status)."
    case .networkUnavailable: "Could not reach DeepSeek. Check your network and try again."
    case .timedOut: "The DeepSeek balance request timed out. Try again."
    case .invalidResponse: "DeepSeek returned balance data Pulse could not read."
    }
  }
}

struct DeepSeekProvider: UsageProviding {
  static let providerID = "deepseek"
  static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

  private let secretStore: any SecretStoring
  private let httpClient: any DeepSeekHTTPClient

  init(
    secretStore: any SecretStoring = KeychainSecretStore(),
    httpClient: any DeepSeekHTTPClient = URLSessionDeepSeekHTTPClient()
  ) {
    self.secretStore = secretStore
    self.httpClient = httpClient
  }

  func fetch() async throws -> UsageSnapshot {
    let apiKey: String
    do {
      guard let saved = try secretStore.read(account: DeepSeekConfiguration.keychainAccount),
        !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { throw DeepSeekUsageError.missingAPIKey }
      apiKey = saved.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch let error as DeepSeekUsageError {
      throw error
    } catch {
      throw DeepSeekUsageError.keychainUnavailable
    }

    var request = URLRequest(url: Self.balanceURL)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
      try Task.checkCancellation()
      let (data, response) = try await httpClient.data(for: request)
      try Task.checkCancellation()
      switch response.statusCode {
      case 200..<300: return try DeepSeekUsageDecoder.decode(data)
      case 401, 403: throw DeepSeekUsageError.invalidCredentials
      case 404, 405: throw DeepSeekUsageError.endpointUnavailable
      case 429: throw DeepSeekUsageError.rateLimited
      default: throw DeepSeekUsageError.serviceStatus(response.statusCode)
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch let error as URLError where error.code == .timedOut {
      throw DeepSeekUsageError.timedOut
    } catch let error as DeepSeekUsageError {
      throw error
    } catch {
      throw DeepSeekUsageError.networkUnavailable
    }
  }
}

enum DeepSeekUsageDecoder {
  static func decode(_ data: Data, fetchedAt: Date? = nil) throws -> UsageSnapshot {
    do {
      let response = try JSONDecoder().decode(BalanceResponse.self, from: data)
      guard !response.balanceInfos.isEmpty else { throw DeepSeekUsageError.invalidResponse }
      var currencies = Set<String>()
      let metrics = try response.balanceInfos.map { balance -> UsageMetric in
        guard ["CNY", "USD"].contains(balance.currency),
          currencies.insert(balance.currency).inserted,
          // Decimal(string:) accepts a valid prefix. Require the entire string.
          balance.totalBalance.range(
            of: #"\A[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)\z"#,
            options: .regularExpression) != nil,
          let amount = Decimal(
            string: balance.totalBalance, locale: Locale(identifier: "en_US_POSIX")),
          !amount.isNaN
        else { throw DeepSeekUsageError.invalidResponse }
        return .balance(amount: amount, currency: balance.currency)
      }
      // is_available describes API funding; a reported zero/negative total is
      // still a valid balance and must not turn into a missing-account state.
      return UsageSnapshot(
        providerID: DeepSeekProvider.providerID, fetchedAt: fetchedAt ?? Date(), metrics: metrics)
    } catch {
      throw DeepSeekUsageError.invalidResponse
    }
  }

  private struct BalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
      case isAvailable = "is_available"
      case balanceInfos = "balance_infos"
    }
  }

  private struct BalanceInfo: Decodable {
    let currency: String
    let totalBalance: String

    enum CodingKeys: String, CodingKey {
      case currency
      case totalBalance = "total_balance"
    }
  }
}
