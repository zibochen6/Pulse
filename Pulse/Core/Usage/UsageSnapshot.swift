import Foundation

/// Provider-neutral values. A quota percentage is never used to represent money.
struct UsageSnapshot: Equatable, Sendable {
  let providerID: String
  let fetchedAt: Date
  let metrics: [UsageMetric]

  var quotaWindows: [QuotaWindow] {
    metrics.compactMap {
      if case .quota(let window) = $0 { return window }
      return nil
    }
  }
}

enum UsageMetric: Equatable, Sendable {
  case quota(QuotaWindow)
  case balance(amount: Decimal, currency: String)
  case cost(amount: Decimal, currency: String, period: String)
  case unavailable(reason: String)
}

struct QuotaWindow: Equatable, Sendable {
  let durationMinutes: Int?
  let remainingPercent: Int?
  let resetsAt: Date?

  var shortLabel: String {
    guard let durationMinutes, durationMinutes > 0 else { return "?" }
    if durationMinutes % 1_440 == 0 { return "\(durationMinutes / 1_440)d" }
    if durationMinutes % 60 == 0 { return "\(durationMinutes / 60)h" }
    return "\(durationMinutes)m"
  }

  var displayName: String {
    guard let durationMinutes else { return "Limit window" }
    if durationMinutes == 300 { return "5-hour window" }
    if durationMinutes == 10_080 { return "Weekly window" }
    return "\(shortLabel) window"
  }
}

protocol UsageProviding: Sendable {
  func fetch() async throws -> UsageSnapshot
}

protocol UsageFailureDescribing: Error {
  var isUnavailable: Bool { get }
  var userMessage: String { get }
}

enum UsageRefreshState: Equatable, Sendable {
  case loading
  case success(UsageSnapshot)
  case unavailable(String)
  case failure(String)
}

enum UsageMenuFormatter {
  static func title(for state: UsageRefreshState) -> String {
    switch state {
    case .loading:
      return "…"
    case .unavailable:
      return "--"
    case .failure:
      return "!"
    case .success(let snapshot):
      let windows = snapshot.quotaWindows
      guard !windows.isEmpty else { return "--" }
      if windows.count == 1, let window = windows.first {
        return window.remainingPercent.map { "\($0)%" } ?? "--"
      }
      return windows.map { window in
        let value = window.remainingPercent.map { "\($0)%" } ?? "--"
        return "\(window.shortLabel) \(value)"
      }.joined(separator: " ")
    }
  }
}
