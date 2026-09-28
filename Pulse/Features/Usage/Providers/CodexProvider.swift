import Foundation

enum CodexUsageError: LocalizedError, Equatable, UsageFailureDescribing {
  case binaryNotFound
  case invalidBinaryOverride
  case launchFailed
  case timeout
  case serverExited
  case serverRejected
  case invalidResponse
  case noQuota

  var isUnavailable: Bool {
    switch self {
    case .binaryNotFound, .invalidBinaryOverride, .noQuota: true
    default: false
    }
  }

  var userMessage: String { errorDescription ?? "Could not refresh Codex usage." }

  var errorDescription: String? {
    switch self {
    case .binaryNotFound:
      "Codex CLI was not found. Install Codex or set CODEX_BIN to its executable."
    case .invalidBinaryOverride:
      "CODEX_BIN does not point to an executable Codex CLI. Check its path."
    case .launchFailed:
      "Could not start the Codex app-server."
    case .timeout:
      "Codex did not respond in time. Try refreshing."
    case .serverExited:
      "Codex closed before returning usage data."
    case .serverRejected:
      "Codex rejected the usage request. Check that you are signed in."
    case .invalidResponse:
      "Codex returned usage data Pulse could not read."
    case .noQuota:
      "Codex did not report a usable quota window."
    }
  }
}

protocol CodexAppServerReading: Sendable {
  func readRateLimits() async throws -> Data
}

struct CodexProvider: UsageProviding {
  private let appServer: any CodexAppServerReading

  init(appServer: any CodexAppServerReading = CodexAppServerTransport()) {
    self.appServer = appServer
  }

  func fetch() async throws -> UsageSnapshot {
    let response = try await appServer.readRateLimits()
    return try CodexRateLimitDecoder.decode(response, fetchedAt: Date())
  }
}

/// The only boundary that knows Codex's JSON response shape.
enum CodexRateLimitDecoder {
  static func decode(_ response: Data, fetchedAt: Date) throws -> UsageSnapshot {
    guard let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
    else { throw CodexUsageError.invalidResponse }
    if object["error"] != nil { throw CodexUsageError.serverRejected }
    guard let rawResult = object["result"] as? [String: Any],
      let resultData = try? JSONSerialization.data(withJSONObject: rawResult),
      let result = try? JSONDecoder().decode(RateLimitsResult.self, from: resultData)
    else { throw CodexUsageError.invalidResponse }

    // A different limit ID may describe a different product. Never present it as Codex.
    let selected: RateLimitSet?
    if let codex = result.rateLimitsByLimitId?["codex"] {
      selected = codex
    } else if let legacy = result.rateLimits,
      legacy.limitId == nil || legacy.limitId == "codex"
    {
      selected = legacy
    } else {
      selected = nil
    }
    guard let selected else { throw CodexUsageError.noQuota }

    let windows = [selected.primary, selected.secondary]
      .compactMap { $0 }
      .map { window -> QuotaWindow in
        let remaining = window.usedPercent.flatMap { used -> Int? in
          guard used.isFinite else { return nil }
          return Int((100 - min(100, max(0, used))).rounded())
        }
        let duration = window.windowDurationMins.flatMap { minutes -> Int? in
          guard minutes.isFinite, minutes > 0, minutes < Double(Int.max) else { return nil }
          return Int(minutes.rounded())
        }
        let reset = window.resetsAt.flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
        return QuotaWindow(durationMinutes: duration, remainingPercent: remaining, resetsAt: reset)
      }
    var unique: [QuotaWindow] = []
    for window in windows where !unique.contains(window) { unique.append(window) }
    unique.sort {
      ($0.durationMinutes ?? Int.max) < ($1.durationMinutes ?? Int.max)
    }
    guard unique.contains(where: { $0.remainingPercent != nil }) else {
      throw CodexUsageError.noQuota
    }
    return UsageSnapshot(
      providerID: "codex", fetchedAt: fetchedAt, metrics: unique.map(UsageMetric.quota))
  }

  private struct RateLimitsResult: Decodable {
    let rateLimits: RateLimitSet?
    let rateLimitsByLimitId: [String: RateLimitSet]?
  }

  private struct RateLimitSet: Decodable {
    let limitId: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
  }

  private struct RateLimitWindow: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Double?
    let resetsAt: Double?
  }
}
