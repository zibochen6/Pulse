import Foundation

protocol UpdateDownloading: Sendable {
  func download(_ asset: UpdateAsset, to destination: URL) async throws
  func data(for asset: UpdateAsset) async throws -> Data
}

/// Downloads release assets into the app's own staging area. The URL policy is
/// enforced on both the request and the final (redirected) URL so a hijacked
/// redirect cannot pull bytes from an unrelated host.
struct URLSessionUpdateDownloader: UpdateDownloading {
  /// A Pulse release is a few megabytes; anything far larger is refused before
  /// it can fill the disk.
  static let maximumArchiveSize = 200 * 1024 * 1024

  let policy: UpdateHostPolicy
  private let session: URLSession

  init(
    session: URLSession = .shared,
    allowedHosts: Set<String> = GitHubUpdateFeed.defaultAllowedHosts
  ) {
    self.session = session
    self.policy = UpdateHostPolicy(allowedHosts: allowedHosts)
  }

  func download(_ asset: UpdateAsset, to destination: URL) async throws {
    guard asset.size <= Self.maximumArchiveSize else {
      throw UpdateDownloadError.tooLarge(asset.size)
    }
    try policy.validate(asset.url)
    var request = URLRequest(url: asset.url, timeoutInterval: 120)
    request.setValue("Pulse", forHTTPHeaderField: "User-Agent")
    let (temporaryURL, response) = try await session.download(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw UpdateFeedError.unsupportedResponse
    }
    guard http.statusCode == 200 else { throw UpdateDownloadError.httpStatus(http.statusCode) }
    try policy.validate(http.url)
    let attributes = try? FileManager.default.attributesOfItem(atPath: temporaryURL.path)
    let byteCount = (attributes?[.size] as? NSNumber)?.intValue ?? 0
    guard byteCount > 0 else { throw UpdateDownloadError.emptyDownload }
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: destination)
    try fileManager.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    do {
      try fileManager.moveItem(at: temporaryURL, to: destination)
    } catch {
      try fileManager.copyItem(at: temporaryURL, to: destination)
    }
  }

  func data(for asset: UpdateAsset) async throws -> Data {
    try policy.validate(asset.url)
    var request = URLRequest(url: asset.url, timeoutInterval: 30)
    request.setValue("Pulse", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw UpdateFeedError.unsupportedResponse
    }
    guard http.statusCode == 200 else { throw UpdateDownloadError.httpStatus(http.statusCode) }
    try policy.validate(http.url)
    return data
  }
}