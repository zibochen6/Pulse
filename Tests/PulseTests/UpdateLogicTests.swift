import Foundation
import XCTest

@testable import Pulse

final class UpdateVersionTests: XCTestCase {
  func testParsesTagsAndBundleVersions() {
    XCTAssertEqual(UpdateVersion(string: "0.1.3"), UpdateVersion(major: 0, minor: 1, patch: 3))
    XCTAssertEqual(UpdateVersion(string: "v0.1.3"), UpdateVersion(major: 0, minor: 1, patch: 3))
    XCTAssertEqual(UpdateVersion(string: " 1.20.0\n"), UpdateVersion(major: 1, minor: 20, patch: 0))
    XCTAssertEqual(UpdateVersion(string: "0.1.3")?.description, "0.1.3")
  }

  func testRejectsAmbiguousVersions() {
    for raw in ["", "0.1", "0.1.3.4", "0.1.3-beta", "v", "x.y.z", "-1.0.0", "0.1."] {
      XCTAssertNil(UpdateVersion(string: raw), raw)
    }
  }

  func testOrdersByNumberNotByString() {
    XCTAssertLessThan(
      UpdateVersion(string: "0.1.9")!, UpdateVersion(string: "0.1.10")!)
    XCTAssertLessThan(
      UpdateVersion(string: "0.9.0")!, UpdateVersion(string: "1.0.0")!)
    XCTAssertFalse(UpdateVersion(string: "0.1.3")! < UpdateVersion(string: "0.1.3")!)
    // A build number only breaks ties within the same marketing version.
    XCTAssertLessThan(
      UpdateVersion(major: 0, minor: 1, patch: 3, build: 7),
      UpdateVersion(major: 0, minor: 1, patch: 3, build: 8))
    XCTAssertLessThan(
      UpdateVersion(major: 0, minor: 1, patch: 2, build: 99),
      UpdateVersion(major: 0, minor: 1, patch: 3, build: 1))
  }

  func testCurrentVersionFallsBackToZeroWhenTheBundleIsUnreadable() {
    let version = UpdateVersion.current(in: PreviewBundle(version: nil, build: nil))
    XCTAssertEqual(version, UpdateVersion(major: 0, minor: 0, patch: 0))
  }

  func testCurrentVersionReadsBundleMetadata() {
    let version = UpdateVersion.current(in: PreviewBundle(version: "0.1.2", build: "6"))
    XCTAssertEqual(version, UpdateVersion(major: 0, minor: 1, patch: 2, build: 6))
  }
}

final class UpdateReleaseParserTests: XCTestCase {
  func testSelectsArchiveChecksumAndDiskImage() throws {
    let release = try UpdateReleaseParser.parse(Self.payload())
    XCTAssertEqual(release.version, UpdateVersion(string: "0.1.3"))
    XCTAssertEqual(release.tagName, "v0.1.3")
    XCTAssertEqual(release.archive.name, "Pulse-0.1.3.zip")
    XCTAssertEqual(release.checksum.name, "Pulse-0.1.3.zip.sha256")
    XCTAssertEqual(release.diskImage?.name, "Pulse-0.1.3.dmg")
    XCTAssertEqual(release.archive.size, 2_500_000)
    XCTAssertEqual(release.archive.sha256, String(repeating: "a", count: 64))
    XCTAssertEqual(release.pageURL?.absoluteString, "https://github.com/zibochen6/Pulse/releases/tag/v0.1.3")
  }

  func testRejectsDraftAndPrereleaseReleases() throws {
    let cases = [
      ("\"draft\": false", "\"draft\": true"),
      ("\"prerelease\": false", "\"prerelease\": true"),
    ]
    for (original, replacement) in cases {
      let data = Data(
        String(decoding: Self.payload(), as: UTF8.self)
          .replacingOccurrences(of: original, with: replacement).utf8)
      XCTAssertThrowsError(try UpdateReleaseParser.parse(data), replacement) { error in
        XCTAssertEqual(error as? UpdateReleaseError, .unsupportedRelease, replacement)
      }
    }
  }

  func testRejectsReleaseWithoutChecksum() {
    let text = String(decoding: Self.payload(), as: UTF8.self)
      .replacingOccurrences(of: "\"name\": \"Pulse-0.1.3.zip.sha256\"", with: "\"name\": \"notes.txt\"")
    XCTAssertThrowsError(try UpdateReleaseParser.parse(Data(text.utf8))) { error in
      XCTAssertEqual(error as? UpdateReleaseError, .missingChecksum)
    }
  }

  func testRejectsMalformedVersionTag() {
    let text = String(decoding: Self.payload(), as: UTF8.self)
      .replacingOccurrences(of: "\"tag_name\": \"v0.1.3\"", with: "\"tag_name\": \"nightly\"")
    XCTAssertThrowsError(try UpdateReleaseParser.parse(Data(text.utf8))) { error in
      XCTAssertEqual(error as? UpdateReleaseError, .malformedVersion("nightly"))
    }
  }

  func testRejectsPayloadThatIsNotARelease() {
    XCTAssertThrowsError(try UpdateReleaseParser.parse(Data("{}".utf8))) { error in
      guard case .malformedPayload = error as? UpdateReleaseError else {
        return XCTFail("Expected malformedPayload, got \(error)")
      }
    }
  }

  func testReadsGitHubAssetDigestOnlyForSHA256() throws {
    XCTAssertEqual(
      UpdateReleaseParser.sha256Hex(fromDigest: "sha256:" + String(repeating: "B", count: 64)),
      String(repeating: "b", count: 64))
    XCTAssertNil(UpdateReleaseParser.sha256Hex(fromDigest: "sha1:abc"))
    XCTAssertNil(UpdateReleaseParser.sha256Hex(fromDigest: "sha256:not-hex"))
  }

  static func payload() -> Data {
    Data(
      """
      {
        "tag_name": "v0.1.3",
        "name": "Pulse 0.1.3",
        "body": "Notes",
        "html_url": "https://github.com/zibochen6/Pulse/releases/tag/v0.1.3",
        "draft": false,
        "prerelease": false,
        "assets": [
          {
            "name": "Pulse-0.1.3.zip",
            "browser_download_url": "https://github.com/zibochen6/Pulse/releases/download/v0.1.3/Pulse-0.1.3.zip",
            "size": 2500000,
            "digest": "sha256:\(String(repeating: "a", count: 64))"
          },
          {
            "name": "Pulse-0.1.3.zip.sha256",
            "browser_download_url": "https://github.com/zibochen6/Pulse/releases/download/v0.1.3/Pulse-0.1.3.zip.sha256",
            "size": 82,
            "digest": "sha256:\(String(repeating: "c", count: 64))"
          },
          {
            "name": "Pulse-0.1.3.dmg",
            "browser_download_url": "https://github.com/zibochen6/Pulse/releases/download/v0.1.3/Pulse-0.1.3.dmg",
            "size": 2400000,
            "digest": "sha256:\(String(repeating: "d", count: 64))"
          }
        ]
      }
      """.utf8)
  }
}

final class UpdateChecksumTests: XCTestCase {
  private func temporaryFile(_ text: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseChecksum-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Pulse-0.1.3.zip")
    try Data(text.utf8).write(to: url)
    return url
  }

  func testParsesShasumOutput() throws {
    let digest = UpdateChecksum.sha256Hex(of: Data("pulse".utf8))
    XCTAssertEqual(try UpdateChecksum.parse("\(digest)  Pulse-0.1.3.zip\n"), digest)
    XCTAssertEqual(try UpdateChecksum.parse("\(digest.uppercased()) *Pulse-0.1.3.zip"), digest)
  }

  func testRejectsMalformedChecksumFiles() {
    for text in ["", "pulse  Pulse-0.1.3.zip", "\(String(repeating: "z", count: 64))  file"] {
      XCTAssertThrowsError(try UpdateChecksum.parse(text), text)
    }
  }

  func testVerifiesAndRejectsMismatchedBytes() throws {
    let url = try temporaryFile("archive-bytes")
    let good = UpdateChecksum.sha256Hex(of: Data("archive-bytes".utf8))
    XCTAssertNoThrow(try UpdateChecksum.verify(fileAt: url, matchesPublishedHex: good))
    XCTAssertThrowsError(try UpdateChecksum.verify(fileAt: url, matchesPublishedHex: String(repeating: "0", count: 64))) {
      guard case .checksumMismatch = $0 as? UpdateVerificationError else {
        return XCTFail("Expected checksumMismatch, got \($0)")
      }
    }
  }

  func testUnreadableFileIsReportedNotCrashed() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID())")
    XCTAssertThrowsError(try UpdateChecksum.sha256Hex(ofFileAt: missing)) {
      guard case .checksumUnreadable = $0 as? UpdateVerificationError else {
        return XCTFail("Expected checksumUnreadable, got \($0)")
      }
    }
  }
}

final class UpdateSignatureReportTests: XCTestCase {
  func testParsesCodesignDetailsReport() {
    let report = UpdateSignatureReport.parse(
      """
      Executable=/Applications/Pulse.app/Contents/MacOS/Pulse
      Identifier=dev.zibochen.Pulse
      Format=app bundle with Mach-O universal (x86_64 arm64)
      CodeDirectory v=20400 size=7222 flags=0x0(none) hashes=219+3 location=embedded
      Authority=Apple Development: Example (ABC123)
      Authority=Apple Worldwide Developer Relations Certification Authority
      Authority=Apple Root CA
      TeamIdentifier=9Y4B7WBUU2
      """)
    XCTAssertEqual(report.identifier, "dev.zibochen.Pulse")
    XCTAssertEqual(report.teamIdentifier, "9Y4B7WBUU2")
    XCTAssertEqual(report.authorities.first, "Apple Development: Example (ABC123)")
    XCTAssertEqual(report.authorities.count, 3)
  }

  func testMissingFieldsStayNil() {
    let report = UpdateSignatureReport.parse("no signature here")
    XCTAssertNil(report.identifier)
    XCTAssertNil(report.teamIdentifier)
    XCTAssertTrue(report.authorities.isEmpty)
  }
}

/// A bundle stand-in so version reading does not depend on the test host build.
private final class PreviewBundle: Bundle, @unchecked Sendable {
  private let version: String?
  private let build: String?

  init(version: String?, build: String?) {
    self.version = version
    self.build = build
    super.init()
  }

  required init?(coder: NSCoder) { nil }

  override func object(forInfoDictionaryKey key: String) -> Any? {
    switch key {
    case "CFBundleShortVersionString": version
    case "CFBundleVersion": build
    default: nil
    }
  }
}