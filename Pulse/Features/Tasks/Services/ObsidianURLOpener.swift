import Foundation

enum ObsidianURLOpener {
  static func url(for fileURL: URL) -> URL? {
    var components = URLComponents()
    components.scheme = "obsidian"
    components.host = "open"
    components.queryItems = [URLQueryItem(name: "path", value: fileURL.path)]
    return components.url
  }
}
