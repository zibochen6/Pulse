import Foundation

struct AntigravityProvider: UsageProviding {
  private let cli: any AntigravityCLIReading

  init(cli: any AntigravityCLIReading = AntigravityCLITransport()) {
    self.cli = cli
  }

  func fetch() async throws -> UsageSnapshot {
    let result = try await cli.readUsage()
    try Task.checkCancellation()
    return try Self.decode(result, fetchedAt: .now)
  }

  static func decode(_ result: AntigravityCLIResult, fetchedAt: Date) throws -> UsageSnapshot {
    let report = try? JSONDecoder().decode(Report.self, from: result.stdout)
    guard result.status == 0, report?.status == "SUCCESS" else {
      let diagnostic = [report?.error ?? "", String(decoding: result.stderr, as: UTF8.self)]
        .joined(separator: "\n")
      if result.status == 0 && diagnostic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw AntigravityUsageError.invalidReport
      }
      throw AntigravityUsageError.fromDiagnostic(diagnostic)
    }
    guard let command = report?.command, command.name == "usage", let data = command.data
    else { throw AntigravityUsageError.invalidReport }

    var windows: [AntigravityQuotaBucket: QuotaWindow] = [:]
    for bucket in data.groups.flatMap(\.buckets) {
      guard let kind = AntigravityQuotaBucket(rawValue: bucket.id), bucket.disabled != true
      else { continue }
      let percent = bucket.remainingFraction.flatMap {
        $0.isFinite && (0...1).contains($0) ? $0 * 100 : nil
      }
      let reset = bucket.resetTime.flatMap(Self.resetDate)
      guard percent != nil || reset != nil else { continue }
      let window = QuotaWindow(
        durationMinutes: kind.durationMinutes, measuredRemainingPercent: percent, resetsAt: reset,
        bucketID: kind.rawValue, displayNameKey: kind.displayNameKey)
      // A duplicate with a measured percentage takes precedence over reset-only data.
      if windows[kind]?.remainingPercent == nil { windows[kind] = window }
    }
    guard !windows.isEmpty else { throw AntigravityUsageError.noQuota }
    return UsageSnapshot(
      providerID: ProviderID.antigravity.rawValue, fetchedAt: fetchedAt,
      metrics: AntigravityQuotaBucket.allCases.compactMap { windows[$0].map(UsageMetric.quota) })
  }

  private static func resetDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions.insert(.withFractionalSeconds)
    return formatter.date(from: value)
  }

  private struct Report: Decodable {
    let status: String
    let command: Command?
    let error: String?
  }

  private struct Command: Decodable {
    let name: String
    let data: CommandData?
  }

  private struct CommandData: Decodable {
    let groups: [Group]
  }

  private struct Group: Decodable {
    let buckets: [Bucket]
  }

  private struct Bucket: Decodable {
    let id: String
    let remainingFraction: Double?
    let resetTime: String?
    let disabled: Bool?

    private enum CodingKeys: String, CodingKey {
      case id
      case remainingFraction = "remaining_fraction"
      case resetTime = "reset_time"
      case disabled
    }
  }
}

enum AntigravityQuotaBucket: String, CaseIterable {
  case fiveHour = "gemini-5h"
  case weekly = "gemini-weekly"
  case argonWeekly = "gemini-argon-wtu-weekly"

  var durationMinutes: Int { self == .fiveHour ? 300 : 10_080 }

  var displayNameKey: String {
    switch self {
    case .fiveHour: "Gemini 5-hour quota"
    case .weekly: "Gemini weekly quota"
    case .argonWeekly: "Gemini 4 Argon weekly quota"
    }
  }
}

enum AntigravityUsageError: UsageFailureDescribing, Equatable {
  case binaryNotFound
  case launchFailed
  case unsupportedCLI
  case signInRequired
  case notEligible
  case network
  case timeout
  case invalidReport
  case noQuota
  case queryFailed

  static func fromDiagnostic(_ diagnostic: String) -> Self {
    let text = diagnostic.lowercased()
    if text.contains("not eligible") || text.contains("not available in your location") {
      return .notEligible
    }
    if text.contains("not authenticated") || text.contains("sign in") || text.contains("sign-in")
      || text.contains("login required") || text.contains("not logged in")
    {
      return .signInRequired
    }
    if text.contains("unknown flag") || text.contains("unknown option")
      || text.contains("unsupported slash command")
    {
      return .unsupportedCLI
    }
    if text.contains("timed out") || text.contains("deadline exceeded")
      || text.contains("i/o timeout")
    {
      return .timeout
    }
    let networkErrors = [
      "network", "failed to connect", "unable to connect", "connection refused",
      "connection reset", "no such host", "broken pipe",
    ]
    let endedConnection = text.split(whereSeparator: \.isNewline).contains {
      let line = $0.trimmingCharacters(in: .whitespaces)
      return line == "eof" || line.hasSuffix(": eof") || line.hasSuffix(": unexpected eof")
    }
    if networkErrors.contains(where: text.contains) || endedConnection {
      return .network
    }
    return .queryFailed
  }

  var isUnavailable: Bool {
    switch self {
    case .binaryNotFound, .unsupportedCLI, .signInRequired, .notEligible, .noQuota: true
    default: false
    }
  }

  var failureKind: UsageFailureKind {
    switch self {
    case .signInRequired: .notConnected
    case .noQuota: .missingData
    default: isUnavailable ? .unavailable : .requestFailed
    }
  }

  var userMessage: String {
    switch self {
    case .binaryNotFound:
      PulseLocalization.string("Install the Antigravity CLI (agy) to check Gemini quotas.")
    case .launchFailed:
      PulseLocalization.string("Could not start the Antigravity CLI.")
    case .unsupportedCLI:
      PulseLocalization.string("Update the Antigravity CLI to check Gemini quotas.")
    case .signInRequired:
      PulseLocalization.string("Sign in to Antigravity in a terminal, then try again.")
    case .notEligible:
      PulseLocalization.string("Antigravity quota is unavailable for this account or region.")
    case .network:
      PulseLocalization.string("Could not reach Antigravity. Check your network and try again.")
    case .timeout:
      PulseLocalization.string("The Antigravity quota check timed out. Try again.")
    case .invalidReport:
      PulseLocalization.string("Could not read the Antigravity quota report.")
    case .noQuota:
      PulseLocalization.string("Antigravity did not report Gemini model quotas.")
    case .queryFailed:
      PulseLocalization.string("Could not check Gemini quotas. Try again.")
    }
  }
}
