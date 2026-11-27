import Foundation

/// A current reading and its recovery path, shared by the menu bar and popover.
struct ProviderUsagePresentation {
  enum Status: Equatable {
    case checking
    case notConnected(String?)
    case credentialsRejected(String)
    case configurationError(String)
    case unavailable(String)
    case failed(String)
    case missing(String?)
    case partial
    case exhausted(QuotaWindow)
    case insufficientBalance
    case accountUnavailable
    case ready
  }

  struct MoneyReading: Identifiable, Equatable {
    enum Kind: String { case balance, allowance, used }

    let kind: Kind
    let amount: Decimal
    let currency: String

    var id: String { "\(kind.rawValue)-\(currency)" }
    var value: String { MoneyFormatter.string(amount, currency: currency) }
  }

  let provider: ProviderID
  let isRefreshing: Bool
  let status: Status
  private let state: UsageRefreshState
  private let snapshot: UsageSnapshot?
  let moneyReadings: [MoneyReading]

  init(
    provider: ProviderID,
    state: UsageRefreshState,
    isConfigured: Bool = true,
    isRefreshing: Bool = false,
    failureKind: UsageFailureKind? = nil,
    configurationError: String? = nil
  ) {
    self.provider = provider
    self.state = state
    self.isRefreshing = isRefreshing

    if !isConfigured {
      snapshot = nil
      moneyReadings = []
      status = configurationError.map(Status.configurationError) ?? .notConnected(nil)
      return
    }

    if case .success(let snapshot) = state {
      self.snapshot = snapshot
      moneyReadings = Self.moneyReadings(in: snapshot)
      status = Self.status(for: snapshot, readings: moneyReadings)
    } else {
      snapshot = nil
      moneyReadings = []
      switch state {
      case .loading, .success: status = .checking
      case .unavailable(let reason):
        status = Self.status(for: failureKind ?? .unavailable, reason: reason)
      case .failure(let reason):
        status = Self.status(for: failureKind ?? .requestFailed, reason: reason)
      }
    }
  }

  @MainActor
  init(
    provider: ProviderID, usage: UsageController, isConfigured: Bool = true,
    configurationError: String? = nil
  ) {
    self.init(
      provider: provider, state: usage.state, isConfigured: isConfigured,
      isRefreshing: usage.isRefreshing, failureKind: usage.failureKind,
      configurationError: configurationError)
  }

  var updatedAt: Date? { snapshot?.fetchedAt }
  var quotaWindows: [QuotaWindow] { snapshot?.quotaWindows ?? [] }
  var balances: [MoneyReading] { moneyReadings.filter { $0.kind == .balance } }
  var isUnlimited: Bool { snapshot?.metrics.contains(.unlimited) ?? false }
  var accessExpiry: Date? {
    snapshot?.metrics.compactMap {
      if case .expiresAt(let date) = $0 { return date }
      return nil
    }.first
  }

  var partialFailureReasons: [String] {
    snapshot?.metrics.compactMap {
      if case .unavailable(let reason) = $0 { return reason }
      return nil
    } ?? []
  }

  var primaryQuota: QuotaWindow? {
    switch provider {
    case .codex:
      let measured = quotaWindows.filter { $0.remainingFraction != nil }
      return measured.first { $0.durationMinutes == 300 } ?? measured.first
    case .antigravity:
      return quotaWindows.first {
        $0.bucketID == AntigravityQuotaBucket.fiveHour.rawValue && $0.remainingFraction != nil
      }
    case .vip, .deepSeek:
      return nil
    }
  }

  var primaryBalance: MoneyReading? {
    let availableBalances = balances
    return availableBalances.first { $0.currency == "CNY" } ?? availableBalances.first
  }

  var statusText: String? {
    switch status {
    case .checking:
      return PulseLocalization.string("Checking…")
    case .notConnected:
      return PulseLocalization.string("Not connected")
    case .credentialsRejected:
      return PulseLocalization.string("Connection failed")
    case .failed, .configurationError:
      return PulseLocalization.string("Could not read data")
    case .unavailable:
      return PulseLocalization.string("Data unavailable")
    case .missing:
      return PulseLocalization.string("No data reported")
    case .partial:
      return PulseLocalization.string("Partial data")
    case .exhausted(let window):
      return PulseLocalization.format("%@ exhausted", window.compactName)
    case .insufficientBalance:
      return PulseLocalization.string("Insufficient balance")
    case .accountUnavailable:
      return PulseLocalization.string("Account unavailable")
    case .ready:
      return nil
    }
  }

  var statusReason: String? {
    switch status {
    case .notConnected(let reason), .missing(let reason): reason
    case .credentialsRejected(let reason), .configurationError(let reason),
      .unavailable(let reason), .failed(let reason):
      reason
    default: nil
    }
  }

  var requiresConfiguration: Bool {
    switch status {
    case .notConnected, .credentialsRejected, .configurationError: true
    default: false
    }
  }

  var showsRetry: Bool {
    switch status {
    case .missing, .unavailable, .failed, .partial: true
    default: false
    }
  }

  var attentionPriority: Int {
    switch status {
    case .exhausted, .insufficientBalance: 3
    case .notConnected(let reason): reason == nil ? 0 : 2
    case .credentialsRejected, .configurationError, .unavailable, .failed, .accountUnavailable: 2
    case .partial: snapshot?.hasPartialDataFailure == true ? 1 : 0
    case .checking, .missing, .ready: 0
    }
  }

  var compactText: String {
    let reading: String
    if status == .ready || (status == .partial && attentionPriority == 0) {
      if let window = primaryQuota, let percent = window.percentageText {
        reading = PulseLocalization.format("%@ left in %@", percent, window.compactName)
      } else if isUnlimited {
        reading = PulseLocalization.string("Unlimited")
      } else if let balance = primaryBalance {
        reading = "\(PulseLocalization.string("Balance")) \(balance.value)"
      } else {
        reading = PulseLocalization.string("Data unavailable")
      }
    } else {
      reading = statusText ?? PulseLocalization.string("Data unavailable")
    }
    return "\(provider.name) · \(reading)"
  }

  /// The system status item's established, Codex-only text layout.
  var menuBarTitle: String {
    switch state {
    case .loading: return "…"
    case .unavailable: return "--"
    case .failure: return "!"
    case .success:
      let windows = quotaWindows
      guard !windows.isEmpty else { return "--" }
      if windows.count == 1 { return windows[0].percentageText ?? "--" }
      return windows.map { "\($0.shortLabel) \($0.percentageText ?? "--")" }.joined(separator: " ")
    }
  }

  static func homeSummary(in readings: [Self]) -> Self? {
    if let urgent = readings.max(by: { $0.attentionPriority < $1.attentionPriority }),
      urgent.attentionPriority > 0
    {
      return urgent
    }
    return readings.first { $0.provider == .codex } ?? readings.first
  }

  private static func status(for failureKind: UsageFailureKind, reason: String) -> Status {
    switch failureKind {
    case .notConnected: .notConnected(reason)
    case .invalidCredentials: .credentialsRejected(reason)
    case .missingData: .missing(reason)
    case .unavailable: .unavailable(reason)
    case .requestFailed: .failed(reason)
    }
  }

  private static func status(for snapshot: UsageSnapshot, readings: [MoneyReading]) -> Status {
    let windows = snapshot.quotaWindows
    if let exhausted = windows.first(where: { $0.remainingFraction == 0 }) {
      return .exhausted(exhausted)
    }
    if snapshot.hasPartialDataFailure { return .partial }
    if !windows.isEmpty {
      guard windows.contains(where: { $0.remainingFraction != nil }) else { return .missing(nil) }
      return windows.contains(where: { $0.remainingFraction == nil }) ? .partial : .ready
    }
    if snapshot.metrics.contains(.unlimited) { return .ready }

    let balances = readings.filter { $0.kind == .balance }
    if snapshot.accountAvailable != true && !balances.isEmpty
      && balances.allSatisfy({ $0.amount <= 0 })
    {
      return .insufficientBalance
    }
    if snapshot.accountAvailable == false { return .accountUnavailable }
    return balances.isEmpty ? .missing(nil) : .ready
  }

  private static func moneyReadings(in snapshot: UsageSnapshot) -> [MoneyReading] {
    snapshot.metrics.compactMap { metric in
      switch metric {
      case .allowance(let amount, let currency) where !amount.isNaN:
        MoneyReading(kind: .allowance, amount: amount, currency: currency)
      case .usage(let amount, let currency) where !amount.isNaN:
        MoneyReading(kind: .used, amount: amount, currency: currency)
      case .balance(let amount, let currency) where !amount.isNaN:
        MoneyReading(kind: .balance, amount: amount, currency: currency)
      default:
        nil
      }
    }
  }
}

extension QuotaWindow {
  fileprivate var compactName: String {
    if bucketID == AntigravityQuotaBucket.argonWeekly.rawValue {
      return PulseLocalization.string("Argon weekly quota")
    }
    switch durationMinutes {
    case 300: return PulseLocalization.string("5-hour quota")
    case 10_080: return PulseLocalization.string("Weekly quota")
    default: return displayName
    }
  }
}
