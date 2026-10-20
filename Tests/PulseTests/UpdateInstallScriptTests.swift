import Foundation
import XCTest

@testable import Pulse

final class UpdateInstallScriptTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseInstallScript-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func plan(
    destination: URL, staged: URL, backup: URL, relaunch: Bool = true
  ) -> UpdateInstallPlan {
    UpdateInstallPlan(
      stagedAppPath: staged.path,
      destinationAppPath: destination.path,
      backupAppPath: backup.path,
      logPath: directory.appendingPathComponent("update.log").path,
      stagingRootPath: directory.appendingPathComponent("Staged", isDirectory: true).path,
      oldProcessIdentifier: 999_999,
      relaunch: relaunch
    )
  }

  func testGeneratedScriptIsValidPosixShell() throws {
    let script = directory.appendingPathComponent("install.sh")
    let destination = directory.appendingPathComponent("Applications with space/Pulse.app")
    let scriptText = UpdateInstallScript.make(
      for: plan(
        destination: destination,
        staged: directory.appendingPathComponent("staged app/Pulse.app"),
        backup: directory.appendingPathComponent("backup/Pulse.app")))
    try Data(scriptText.utf8).write(to: script)
    let result = try UpdateShell.run("/bin/sh", ["-n", script.path])
    XCTAssertEqual(result.status, 0, result.stderr)
    // Paths with spaces must survive quoting.
    XCTAssertTrue(scriptText.contains("'\(destination.path)'"))
  }

  func testScriptEncodesEveryOrderedStep() throws {
    let text = UpdateInstallScript.make(
      for: plan(
        destination: directory.appendingPathComponent("Pulse.app"),
        staged: directory.appendingPathComponent("Staged/Pulse.app"),
        backup: directory.appendingPathComponent("Backup/Pulse.app")))
    // Wait for the old pid before touching the bundle.
    let waitIndex = try XCTUnwrap(text.range(of: "kill -0 \"$OLD_PID\""))
    let backupIndex = try XCTUnwrap(text.range(of: "/usr/bin/ditto \"$DESTINATION\" \"$BACKUP\""))
    let replaceIndex = try XCTUnwrap(text.range(of: "/usr/bin/ditto \"$STAGED\" \"$DESTINATION\""))
    let verifyIndex = try XCTUnwrap(text.range(of: "--verify --deep --strict"))
    XCTAssertLessThan(waitIndex.lowerBound, backupIndex.lowerBound)
    XCTAssertLessThan(backupIndex.lowerBound, replaceIndex.lowerBound)
    XCTAssertLessThan(replaceIndex.lowerBound, verifyIndex.lowerBound)
    XCTAssertTrue(text.contains("OLD_PID=999999"))
    XCTAssertTrue(text.contains("RELAUNCH=1"))
  }

  func testQuoteEscapesEmbeddedSingleQuotes() {
    XCTAssertEqual(UpdateInstallScript.quoted("/tmp/plain"), "'/tmp/plain'")
    XCTAssertEqual(
      UpdateInstallScript.quoted("/tmp/it's here"),
      "'/tmp/it'\\''s here'")
  }

  func testFailedSignatureVerificationRestoresThePreviousApp() throws {
    let destination = directory.appendingPathComponent("Applications/Pulse.app")
    let staged = directory.appendingPathComponent("Staged/Pulse.app")
    let backup = directory.appendingPathComponent("Backup/Pulse.app")
    // Previous app has a marker file; the staged bundle is unsigned, so the
    // script must reject it and restore the previous content.
    try FileManager.default.createDirectory(
      at: destination.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try Data("previous".utf8).write(
      to: destination.appendingPathComponent("Contents/marker.txt"))
    try FileManager.default.createDirectory(
      at: staged.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try Data("staged".utf8).write(to: staged.appendingPathComponent("Contents/marker.txt"))

    let script = directory.appendingPathComponent("install.sh")
    try Data(
      UpdateInstallScript.make(
        for: plan(destination: destination, staged: staged, backup: backup, relaunch: false)
      ).utf8
    ).write(to: script)
    let result = try UpdateShell.run("/bin/sh", [script.path])
    XCTAssertEqual(result.status, 1, "The unsigned staged bundle must fail verification")

    let restored = try String(
      contentsOf: destination.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
    XCTAssertEqual(restored, "previous", "The previous app must be restored")
    let log = try String(
      contentsOf: directory.appendingPathComponent("update.log"), encoding: .utf8)
    XCTAssertTrue(log.contains("restoring the previous app"), log)
  }

  func testSuccessfulInstallationReplacesTheBundleAndCleansStaging() throws {
    // Use the running app's signature only as a parse target: an ad-hoc signed
    // temporary bundle is enough to exercise the happy path.
    let destination = directory.appendingPathComponent("Applications/Pulse.app")
    let staged = directory.appendingPathComponent("Staged/Pulse.app")
    let backup = directory.appendingPathComponent("Backup/Pulse.app")
    try makeSignedBundle(at: staged)
    try FileManager.default.createDirectory(
      at: destination.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try Data("previous".utf8).write(
      to: destination.appendingPathComponent("Contents/marker.txt"))
    try FileManager.default.createDirectory(
      at: directory.appendingPathComponent("Staged/Leftover"),
      withIntermediateDirectories: true)

    let script = directory.appendingPathComponent("install.sh")
    try Data(
      UpdateInstallScript.make(
        for: plan(destination: destination, staged: staged, backup: backup, relaunch: false)
      ).utf8
    ).write(to: script)
    let result = try UpdateShell.run("/bin/sh", [script.path])
    XCTAssertEqual(result.status, 0, result.stderr)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: destination.appendingPathComponent("Contents/Info.plist").path))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: destination.appendingPathComponent("Contents/marker.txt").path))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: directory.appendingPathComponent("Staged").path),
      "Staging is removed after a successful install")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: backup.path), "The previous app is retained")
  }

  private func makeSignedBundle(at url: URL) throws {
    let contents = url.appendingPathComponent("Contents")
    let macOS = contents.appendingPathComponent("MacOS")
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    let info: [String: Any] = [
      "CFBundleIdentifier": "dev.zibochen.Pulse",
      "CFBundleExecutable": "Pulse",
      "CFBundleShortVersionString": "0.1.3",
      "CFBundleVersion": "7",
      "CFBundlePackageType": "APPL",
    ]
    let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try plist.write(to: contents.appendingPathComponent("Info.plist"))
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: macOS.appendingPathComponent("Pulse"))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: macOS.appendingPathComponent("Pulse").path)
    let signing = try UpdateShell.run("/usr/bin/codesign", [
      "--force", "--sign", "-", url.path,
    ])
    XCTAssertEqual(signing.status, 0, signing.stderr)
  }
}