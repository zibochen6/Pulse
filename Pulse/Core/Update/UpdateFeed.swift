import Foundation

enum UpdateFeedError: LocalizedError, Equatable {
  case unsupportedResponse
  case httpStatus(Int)
  case disallowedHost(String)

  var errorDescription: String? {
    switch self {
    case .unsupportedResponse: "Pulse received an unexpected answer while checking for updates."
    case .httpStatus(let code):
      code == 403 || code == 429
        ? "GitHub is rate-limiting update checks. Pulse will try again later."
        : "GitHub answered the update check with HTTP \(code)."
    case .disallowedHost(let host):
      "The update check was redirected to an untrusted host “\(host)”."
    }
  }
}

enum UpdateDownloadError: LocalizedError, Equatable {
  case httpStatus(Int)
  case disallowedHost(String)
  case tooLarge(Int)
  case emptyDownload

  var errorDescription: String? {
    switch self {
    case .httpStatus(let code): "The update download failed with HTTP \(code)."
    case .disallowedHost(let host): "The download was redirected to an untrusted host “\(host)”."
    case .tooLarge(let bytes): "The update download is unexpectedly large (\(bytes) bytes)."
    case .emptyDownload: "The update download was empty."
    }
  }
}

/// Only GitHub hosts that can legitimately serve a Pulse release are accepted,
/// including the release-asset CDN a download redirects to.
struct UpdateHostPolicy: Sendable {
  let allowedHosts: Set<String>

  func validate(_ url: URL?) throws {
    guard let url, let host = url.host?.lowercased() else {
      throw UpdateFeedError.unsupportedResponse
    }
    guard url.scheme?.lowercased() == "https" else {
      // The local acceptance feed runs on loopback over plain HTTP.
      if url.isLoopbackAcceptanceFeed { return }
      throw UpdateFeedError.disallowedHost(host)
    }
    guard allowedHosts.contains(host) || url.isLoopbackAcceptanceFeed else {
      throw UpdateFeedError.disallowedHost(host)
    }
  }
}

extension URL {
  /// The only non-HTTPS feed accepted is the loopback override used to rehearse
  /// updates on one machine; production releases are always fetched over TLS.
  var isLoopbackAcceptanceFeed: Bool {
    guard let host = host?.lowercased() else { return false }
    return host == "127.0.0.1" || host == "localhost" || host == "::1"
  }
}

protocol UpdateFeedFetching: Sendable {
  func latestRelease() async throws -> UpdateRelease
}

/// Reads the repository's newest published release. Drafts and prereleases are
/// rejected by the parser, so a staged or upcoming build is never offered.
struct GitHubUpdateFeed: UpdateFeedFetching {
  static let repository = "zibochen6/Pulse"
  static let defaultFeedURL = URL(
    string: "https://api.github.com/repos/\(repository)/releases/latest")!
  static let defaultAllowedHosts: Set<String> = [
    "api.github.com", "github.com", "release-assets.githubusercontent.com",
    "objects.githubusercontent.com", "raw.githubusercontent.com",
  ]

  let feedURL: URL
  let policy: UpdateHostPolicy
  private let session: URLSession

  init(feedURL: URL = GitHubUpdateFeed.configuredFeedURL, session: URLSession = .shared) {
    self.feedURL = feedURL
    var hosts = GitHubUpdateFeed.defaultAllowedHosts
    if let host = feedURL.host?.lowercased() { hosts.insert(host) }
    self.policy = UpdateHostPolicy(allowedHosts: hosts)
    self.session = session
  }

  /// `PULSE_UPDATE_FEED_URL` exists so the update path can be rehearsed against
  /// a local feed. It changes only where the release description is read from;
  /// every checksum and signature check still runs.
  static var configuredFeedURL: URL {
    if let raw = ProcessInfo.processInfo.environment["PULSE_UPDATE_FEED_URL"],
      let url = URL(string: raw), url.host != nil
    {
      return url
    }
    return defaultFeedURL
  }

  func latestRelease() async throws -> UpdateRelease {
    var request = URLRequest(url: feedURL, timeoutInterval: 20)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("Pulse", forHTTPHeaderField: "User-Agent")
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw UpdateFeedError.unsupportedResponse
    }
    guard http.statusCode == 200 else { throw UpdateFeedError.httpStatus(http.statusCode) }
    try policy.validate(http.url ?? feedURL)
    return try UpdateReleaseParser.parse(data)
  }
}