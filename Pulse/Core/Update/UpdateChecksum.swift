import CryptoKit
import Foundation

/// SHA-256 helpers for update archives and their published `.sha256` files.
enum UpdateChecksum {
  static func sha256Hex(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func sha256Hex(ofFileAt url: URL) throws -> String {
    let data: Data
    do {
      data = try Data(contentsOf: url, options: [.mappedIfSafe])
    } catch {
      throw UpdateVerificationError.checksumUnreadable(error.localizedDescription)
    }
    return sha256Hex(of: data)
  }

  /// `shasum -a 256` writes `<hex>  <name>`; the release publishes exactly that
  /// shape so users can verify downloads by hand. Only the digest is used here.
  static func parse(_ text: String) throws -> String {
    for line in text.split(whereSeparator: \.isNewline) {
      let token = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
      let candidate = token.lowercased()
      if candidate.count == 64, candidate.allSatisfy(\.isHexDigit) { return candidate }
    }
    throw UpdateVerificationError.checksumMalformed
  }

  /// Compares the published digest with the bytes on disk. Any mismatch is
  /// terminal: the archive is never unpacked or installed.
  static func verify(fileAt url: URL, matchesPublishedHex publishedHex: String) throws {
    let actual = try sha256Hex(ofFileAt: url)
    let expected = publishedHex.lowercased()
    guard actual == expected else {
      throw UpdateVerificationError.checksumMismatch(expected: expected, actual: actual)
    }
  }
}