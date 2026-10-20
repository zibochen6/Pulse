import Foundation

/// One downloadable file attached to a GitHub release.
struct UpdateAsset: Equatable, Sendable {
  let name: String
  let url: URL
  let size: Int
  /// Hex SHA-256 supplied by GitHub's asset metadata when available.
  let sha256: String?

  init(name: String, url: URL, size: Int, sha256: String? = nil) {
    self.name = name
    self.url = url
    self.size = size
    self.sha256 = sha256
  }
}

/// The parts of a published release the updater needs.
struct UpdateRelease: Equatable, Sendable {
  let version: UpdateVersion
  let tagName: String
  let title: String
  let notes: String
  let pageURL: URL?
  /// The archive the updater installs, and the checksum file that authenticates
  /// it. Both are required: an archive without a published digest is not
  /// installable.
  let archive: UpdateAsset
  let checksum: UpdateAsset
  /// Kept for reference and for the "release notes" link; the updater never
  /// mounts a disk image.
  let diskImage: UpdateAsset?
}

enum UpdateReleaseError: LocalizedError, Equatable {
  case malformedPayload(String)
  case malformedVersion(String)
  case unsupportedRelease
  case missingArchive
  case missingChecksum
  case malformedAssetURL(String)

  var errorDescription: String? {
    switch self {
    case .malformedPayload(let detail):
      "Pulse could not read the update information from GitHub. \(detail)"
    case .malformedVersion(let tag):
      "The latest release has an unrecognised version tag “\(tag)”."
    case .unsupportedRelease:
      "The latest release is a draft or prerelease, so Pulse will not install it."
    case .missingArchive: "The latest release has no update archive."
    case .missingChecksum: "The latest release has no checksum file for its update archive."
    case .malformedAssetURL(let name): "The download address for “\(name)” is not usable."
    }
  }
}

/// Decodes the GitHub `releases/latest` payload. Parsing is deliberately strict:
/// an ambiguous payload produces an error instead of a best-guess install.
enum UpdateReleaseParser {
  private struct Payload: Decodable {
    struct Asset: Decodable {
      let name: String
      let browserDownloadURL: String
      let size: Int
      let digest: String?

      enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case digest
      }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
      case tagName = "tag_name"
      case name
      case body
      case htmlURL = "html_url"
      case draft
      case prerelease
      case assets
    }
  }

  static func parse(_ data: Data) throws -> UpdateRelease {
    let payload: Payload
    do {
      payload = try JSONDecoder().decode(Payload.self, from: data)
    } catch {
      throw UpdateReleaseError.malformedPayload(error.localizedDescription)
    }
    guard !payload.draft && !payload.prerelease else {
      throw UpdateReleaseError.unsupportedRelease
    }
    guard let version = UpdateVersion(string: payload.tagName) else {
      throw UpdateReleaseError.malformedVersion(payload.tagName)
    }
    let assets = try payload.assets.map { asset -> UpdateAsset in
      guard let url = URL(string: asset.browserDownloadURL) else {
        throw UpdateReleaseError.malformedAssetURL(asset.name)
      }
      return UpdateAsset(
        name: asset.name, url: url, size: asset.size,
        sha256: asset.digest.flatMap(sha256Hex(fromDigest:)))
    }
    let archiveName = "Pulse-\(version).zip"
    guard
      let archive = assets.first(where: { $0.name == archiveName })
        ?? assets.first(where: { $0.name.hasSuffix(".zip") && !$0.name.hasSuffix(".sha256") })
    else { throw UpdateReleaseError.missingArchive }
    guard
      let checksum = assets.first(where: { $0.name == "\(archive.name).sha256" })
        ?? assets.first(where: { $0.name.hasSuffix(".zip.sha256") })
    else { throw UpdateReleaseError.missingChecksum }
    let diskImage =
      assets.first(where: { $0.name == "Pulse-\(version).dmg" })
      ?? assets.first(where: { $0.name.hasSuffix(".dmg") })
    return UpdateRelease(
      version: version,
      tagName: payload.tagName,
      title: payload.name ?? payload.tagName,
      notes: payload.body ?? "",
      pageURL: payload.htmlURL.flatMap(URL.init(string:)),
      archive: archive,
      checksum: checksum,
      diskImage: diskImage
    )
  }

  /// GitHub reports `sha256:<hex>`; only that algorithm is understood.
  static func sha256Hex(fromDigest digest: String) -> String? {
    let prefix = "sha256:"
    guard digest.hasPrefix(prefix) else { return nil }
    let value = String(digest.dropFirst(prefix.count)).lowercased()
    guard value.count == 64, value.allSatisfy(\.isHexDigit) else { return nil }
    return value
  }
}