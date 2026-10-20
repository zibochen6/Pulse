import Foundation

/// Every way a downloaded update can be rejected. All of them are fatal for the
/// download and none of them may modify the installed app.
enum UpdateVerificationError: LocalizedError, Equatable {
  case checksumUnreadable(String)
  case checksumMalformed
  case checksumMismatch(expected: String, actual: String)
  case archiveLayout
  case unreadableBundle(String)
  case bundleIdentifierMismatch(expected: String, actual: String)
  case versionMismatch(expected: String, actual: String)
  case signatureInvalid(String)
  case untrustedTeam(expected: String, actual: String)
  case untrustedAuthority(String)
  case unsupportedLocation(String)

  var errorDescription: String? {
    switch self {
    case .checksumUnreadable(let detail):
      "Pulse could not read the update checksum. \(detail)"
    case .checksumMalformed:
      "The update checksum file is not in the expected format."
    case .checksumMismatch:
      "The downloaded update does not match its published checksum, so it was discarded."
    case .archiveLayout:
      "The update archive does not contain exactly one Pulse application."
    case .unreadableBundle(let detail):
      "Pulse could not read the downloaded application. \(detail)"
    case .bundleIdentifierMismatch:
      "The downloaded application is not Pulse. Nothing was changed."
    case .versionMismatch:
      "The downloaded application reports a different version than its release."
    case .signatureInvalid(let detail):
      "The downloaded application has an invalid code signature. \(detail)"
    case .untrustedTeam:
      "The downloaded application is not signed by the expected Apple team."
    case .untrustedAuthority:
      "The downloaded application is not signed with the expected certificate."
    case .unsupportedLocation:
      "Pulse can only update an application installed in a writable location."
    }
  }
}