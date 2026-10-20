import Foundation

/// The identity fields of a `codesign -dv --verbose=2` report.
struct UpdateSignatureReport: Equatable, Sendable {
  let identifier: String?
  let teamIdentifier: String?
  let authorities: [String]

  /// `codesign -dv` writes its report to standard error, one `Key=Value` pair
  /// per line; only the keys the updater trusts are read.
  static func parse(_ output: String) -> UpdateSignatureReport {
    var identifier: String?
    var teamIdentifier: String?
    var authorities: [String] = []
    for line in output.split(whereSeparator: \.isNewline) {
      let text = line.trimmingCharacters(in: .whitespaces)
      if text.hasPrefix("Identifier=") {
        identifier = String(text.dropFirst("Identifier=".count))
      } else if text.hasPrefix("TeamIdentifier=") {
        teamIdentifier = String(text.dropFirst("TeamIdentifier=".count))
      } else if text.hasPrefix("Authority=") {
        authorities.append(String(text.dropFirst("Authority=".count)))
      }
    }
    return UpdateSignatureReport(
      identifier: identifier, teamIdentifier: teamIdentifier, authorities: authorities)
  }
}

protocol UpdateBundleVerifying: Sendable {
  /// Throws unless the bundle is a validly signed Pulse build by the team the
  /// running app trusts, reporting exactly `expectedVersion`.
  func verify(appBundle: URL, expectedVersion: UpdateVersion) throws
}

/// Verifies a downloaded app bundle against the same certificate the running
/// app is signed with. This is the updater's trust anchor: a compromised
/// release account cannot produce a bundle signed by the local team.
struct CodeSigningBundleVerifier: UpdateBundleVerifying {
  let bundleIdentifier: String
  let teamIdentifier: String
  let requiredAuthorityFragment: String

  init(
    bundleIdentifier: String = "dev.zibochen.Pulse",
    teamIdentifier: String = "9Y4B7WBUU2",
    requiredAuthorityFragment: String = "Apple Development"
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.teamIdentifier = teamIdentifier
    self.requiredAuthorityFragment = requiredAuthorityFragment
  }

  func verify(appBundle: URL, expectedVersion: UpdateVersion) throws {
    let signature = try UpdateShell.run("/usr/bin/codesign", [
      "--verify", "--deep", "--strict", "--verbose=2", appBundle.path,
    ])
    guard signature.succeeded else {
      throw UpdateVerificationError.signatureInvalid(
        signature.stderr.isEmpty ? "codesign exited with \(signature.status)" : signature.stderr)
    }
    let details = try UpdateShell.run("/usr/bin/codesign", [
      "-dv", "--verbose=2", appBundle.path,
    ])
    let report = UpdateSignatureReport.parse(details.combined)
    guard report.identifier == bundleIdentifier else {
      throw UpdateVerificationError.bundleIdentifierMismatch(
        expected: bundleIdentifier, actual: report.identifier ?? "none")
    }
    guard report.teamIdentifier == teamIdentifier else {
      throw UpdateVerificationError.untrustedTeam(
        expected: teamIdentifier, actual: report.teamIdentifier ?? "none")
    }
    guard
      report.authorities.contains(where: { $0.contains(requiredAuthorityFragment) })
    else {
      throw UpdateVerificationError.untrustedAuthority(
        report.authorities.first ?? "no signing authority")
    }
    try verifyVersion(appBundle: appBundle, expectedVersion: expectedVersion)
  }

  private func verifyVersion(appBundle: URL, expectedVersion: UpdateVersion) throws {
    let infoURL = appBundle.appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: infoURL),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let info = plist as? [String: Any]
    else {
      throw UpdateVerificationError.unreadableBundle("The bundle has no readable Info.plist.")
    }
    let shortVersion = info["CFBundleShortVersionString"] as? String
    guard shortVersion == expectedVersion.description else {
      throw UpdateVerificationError.versionMismatch(
        expected: expectedVersion.description, actual: shortVersion ?? "none")
    }
    if let expectedBuild = expectedVersion.build {
      let actualBuild = (info["CFBundleVersion"] as? String).flatMap(Int.init)
      guard actualBuild == expectedBuild else {
        throw UpdateVerificationError.versionMismatch(
          expected: "\(expectedVersion.description) (\(expectedBuild))",
          actual: "\(shortVersion ?? "none") (\(actualBuild.map(String.init) ?? "none"))")
      }
    }
  }
}