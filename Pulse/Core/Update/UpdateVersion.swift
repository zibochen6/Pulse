import Foundation

/// A published Pulse version. Marketing versions are the contract users and
/// GitHub tags see; the build number only breaks ties between two builds of the
/// same marketing version, which happens when a release is repackaged.
struct UpdateVersion: Comparable, Equatable, CustomStringConvertible, Sendable {
  let major: Int
  let minor: Int
  let patch: Int
  let build: Int?

  init(major: Int, minor: Int, patch: Int, build: Int? = nil) {
    self.major = major
    self.minor = minor
    self.patch = patch
    self.build = build
  }

  /// Accepts the tag form (`v0.1.3`) and the bundle form (`0.1.3`). Anything
  /// else - including prerelease suffixes - is rejected rather than guessed at,
  /// because a wrong comparison would install the wrong build.
  init?(string rawValue: String) {
    var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3,
      parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
      let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2])
    else { return nil }
    self.init(major: major, minor: minor, patch: patch)
  }

  var description: String { "\(major).\(minor).\(patch)" }

  /// The version of the running app. A missing or unreadable bundle version is
  /// reported as 0.0.0 so a corrupt development build never claims to be newer
  /// than a real release.
  static func current(in bundle: Bundle = .main) -> UpdateVersion {
    let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let buildText = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    let build = buildText.flatMap(Int.init)
    guard let marketing, var version = UpdateVersion(string: marketing) else {
      return UpdateVersion(major: 0, minor: 0, patch: 0, build: build)
    }
    version = UpdateVersion(
      major: version.major, minor: version.minor, patch: version.patch, build: build)
    return version
  }

  static func < (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
    // Only compare build numbers when both are known; a release asset without a
    // build number must not look newer than the installed app.
    return (lhs.build ?? 0) < (rhs.build ?? 0)
  }
}