import Foundation

/// Provider-neutral values. A quota percentage is never used to represent money.
struct UsageSnapshot: Equatable, Sendable {
  let providerID: String
  let fetchedAt: Date
  let metrics: [UsageMetric]
  /// Some services report separately whether the account can make requests.
  let accountAvailable: Bool?

  init(providerID: String, fetchedAt: Date, metrics: [UsageMetric], accountAvailable: Bool? = nil) {
    self.providerID = providerID
    self.fetchedAt = fetchedAt
    self.metrics = metrics
    self.accountAvailable = accountAvailable
  }

  var hasPartialDataFailure: Bool {
    metrics.contains {
      if case .unavailable = $0 { return true }
      return false
    }
  }

  var quotaWindows: [QuotaWindow] {
    metrics.compactMap {
      if case .quota(let window) = $0 { return window }
      return nil
    }
  }
}

enum UsageMetric: Equatable, Sendable {
  case quota(QuotaWindow)
  case allowance(amount: Decimal, currency: String)
  case usage(amount: Decimal, currency: String)
  case balance(amount: Decimal, currency: String)
  case cost(amount: Decimal, currency: String, period: String)
  case expiresAt(Date)
  case unlimited
  case unavailable(reason: String)
}

struct QuotaWindow: Equatable, Sendable {
  let durationMinutes: Int?
  let resetsAt: Date?
  let bucketID: String?
  private let measuredRemainingPercent: Double?
  private let displayNameKey: String?

  init(
    durationMinutes: Int?, remainingPercent: Int?, resetsAt: Date?,
    bucketID: String? = nil, displayNameKey: String? = nil
  ) {
    self.init(
      durationMinutes: durationMinutes, measuredRemainingPercent: remainingPercent.map(Double.init),
      resetsAt: resetsAt, bucketID: bucketID, displayNameKey: displayNameKey)
  }

  init(
    durationMinutes: Int?, measuredRemainingPercent: Double?, resetsAt: Date?,
    bucketID: String? = nil, displayNameKey: String? = nil
  ) {
    self.durationMinutes = durationMinutes
    self.measuredRemainingPercent = measuredRemainingPercent.flatMap { value in
      (0...100).contains(value) ? value : nil
    }
    self.resetsAt = resetsAt
    self.bucketID = bucketID
    self.displayNameKey = displayNameKey
  }

  var remainingPercent: Int? { measuredRemainingPercent.map { Int($0.rounded()) } }
  var remainingFraction: Double? { measuredRemainingPercent.map { $0 / 100 } }

  var percentageText: String? {
    guard let measuredRemainingPercent, let remainingPercent else { return nil }
    if measuredRemainingPercent > 0 && measuredRemainingPercent < 1 { return "<1%" }
    return "\(remainingPercent)%"
  }

  var shortLabel: String {
    guard let durationMinutes, durationMinutes > 0 else { return "?" }
    if durationMinutes % 1_440 == 0 { return "\(durationMinutes / 1_440)d" }
    if durationMinutes % 60 == 0 { return "\(durationMinutes / 60)h" }
    return "\(durationMinutes)m"
  }

  var displayName: String {
    if let displayNameKey { return PulseLocalization.string(displayNameKey) }
    guard let durationMinutes, durationMinutes > 0 else {
      return PulseLocalization.string("Limit window")
    }
    if durationMinutes == 300 { return PulseLocalization.string("5-hour window") }
    if durationMinutes == 10_080 { return PulseLocalization.string("Weekly window") }
    return PulseLocalization.format("%@ window", shortLabel)
  }
}

protocol UsageProviding: Sendable {
  func fetch() async throws -> UsageSnapshot
}

enum UsageFailureKind: Equatable, Sendable {
  case notConnected
  case invalidCredentials
  case missingData
  case unavailable
  case requestFailed
}

protocol UsageFailureDescribing: Error {
  var isUnavailable: Bool { get }
  var userMessage: String { get }
  var failureKind: UsageFailureKind { get }
}

extension UsageFailureDescribing {
  var failureKind: UsageFailureKind { isUnavailable ? .unavailable : .requestFailed }
}

enum UsageRefreshState: Equatable, Sendable {
  case loading
  case success(UsageSnapshot)
  case unavailable(String)
  case failure(String)
}

enum UsageMenuFormatter {
  static func title(for state: UsageRefreshState) -> String {
    ProviderUsagePresentation(provider: .codex, state: state).menuBarTitle
  }
}
