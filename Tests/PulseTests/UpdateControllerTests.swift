import Foundation
import XCTest

@testable import Pulse

@MainActor
final class UpdateControllerTests: XCTestCase {
  private var directory: URL!
  private var destination: URL!
  private var preferences: UpdatePreferences!

  override func setUp() async throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PulseUpdateController-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    destination = directory.appendingPathComponent("Applications/Pulse.app", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let suite = "PulseUpdateTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    preferences = UpdatePreferences(defaults: defaults)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: directory)
  }

  // MARK: - Fixtures

  private func makeRelease(version: String = "0.2.0", archiveBytes: Data = Data("archive".utf8))
    -> (UpdateRelease, StubUpdateDownloader, URL)
  {
    let appURL = directory.appendingPathComponent("Expanded/Pulse.app", isDirectory: true)
    let checksum = UpdateChecksum.sha256Hex(of: archiveBytes)
    let release = UpdateRelease(
      version: UpdateVersion(string: version)!,
      tagName: "v\(version)",
      title: "Pulse \(version)",
      notes: "Notes",
      pageURL: URL(string: "https://github.com/zibochen6/Pulse/releases/tag/v\(version)"),
      archive: UpdateAsset(
        name: "Pulse-\(version).zip",
        url: URL(string: "https://github.com/zibochen6/Pulse/releases/download/v\(version)/Pulse-\(version).zip")!,
        size: archiveBytes.count,
        sha256: checksum),
      checksum: UpdateAsset(
        name: "Pulse-\(version).zip.sha256",
        url: URL(string: "https://github.com/zibochen6/Pulse/releases/download/v\(version)/Pulse-\(version).zip.sha256")!,
        size: 100),
      diskImage: nil
    )
    let downloader = StubUpdateDownloader(
      archiveBytes: archiveBytes, checksumText: "\(checksum)  Pulse-\(version).zip\n")
    return (release, downloader, appURL)
  }

  private func makeController(
    release: UpdateRelease,
    downloader: StubUpdateDownloader,
    appURL: URL,
    verifierFailure: Error? = nil,
    installer: RecordingUpdateInstaller = RecordingUpdateInstaller(),
    applyAutomatically: Flag = Flag(false),
    terminated: Flag = Flag(false),
    currentVersion: UpdateVersion = UpdateVersion(major: 0, minor: 1, patch: 3, build: 7),
    requiresApplicationsFolder: Bool = false
  ) -> UpdateController {
    UpdateController(
      feed: StubUpdateFeed(release: release),
      downloader: downloader,
      unarchiver: StubUpdateUnarchiver(appURL: appURL),
      verifier: StubUpdateVerifier(failure: verifierFailure),
      installer: installer,
      preferences: preferences,
      currentVersion: currentVersion,
      destinationAppURL: destination,
      supportDirectory: directory.appendingPathComponent("Update", isDirectory: true),
      logsDirectory: directory.appendingPathComponent("Logs", isDirectory: true),
      requiresApplicationsFolder: requiresApplicationsFolder,
      canApplyAutomatically: { applyAutomatically.value },
      terminate: { terminated.value = true },
      now: { Date(timeIntervalSince1970: 1_800_000_000) },
      checkInterval: 60,
      launchDelay: 0
    )
  }

  // MARK: - Tests

  func testNewerReleaseIsDownloadedVerifiedAndStaged() async throws {
    let (release, downloader, appURL) = makeRelease()
    let installer = RecordingUpdateInstaller()
    let controller = makeController(
      release: release, downloader: downloader, appURL: appURL, installer: installer)
    await controller.checkForUpdates()

    guard case .staged(let staged) = controller.phase else {
      return XCTFail("Expected staged, got \(controller.phase)")
    }
    XCTAssertEqual(staged.release.version, UpdateVersion(string: "0.2.0"))
    XCTAssertEqual(staged.appBundleURL, appURL)
    XCTAssertEqual(controller.stagedRelease?.tagName, "v0.2.0")
    XCTAssertEqual(controller.statusText, "Pulse 0.2.0 is ready. Restart to update.")
    XCTAssertTrue(installer.plans.isEmpty, "Nothing is installed while a draft may be open")
    XCTAssertEqual(preferences.lastCheckDate, Date(timeIntervalSince1970: 1_800_000_000))
  }

  func testAutomaticInstallRunsWhenTheAppIsIdle() async throws {
    let (release, downloader, appURL) = makeRelease()
    let installer = RecordingUpdateInstaller()
    let terminated = Flag(false)
    let controller = makeController(
      release: release, downloader: downloader, appURL: appURL, installer: installer,
      applyAutomatically: Flag(true), terminated: terminated)
    await controller.checkForUpdates()

    XCTAssertEqual(installer.plans.count, 1)
    XCTAssertEqual(installer.plans.first?.relaunch, true)
    XCTAssertEqual(installer.plans.first?.destinationAppPath, destination.path)
    XCTAssertTrue(terminated.value, "Pulse restarts into the update")
  }

  func testChecksumMismatchDiscardsTheDownloadAndKeepsTheApp() async throws {
    let (release, _, appURL) = makeRelease()
    let downloader = StubUpdateDownloader(
      archiveBytes: Data("archive".utf8),
      checksumText: String(repeating: "0", count: 64) + "  Pulse-0.2.0.zip\n")
    let installer = RecordingUpdateInstaller()
    let controller = makeController(
      release: release, downloader: downloader, appURL: appURL, installer: installer)
    await controller.checkForUpdates()

    guard case .failed(let message) = controller.phase else {
      return XCTFail("Expected failure, got \(controller.phase)")
    }
    XCTAssertTrue(message.contains("checksum"), message)
    XCTAssertTrue(installer.plans.isEmpty)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("Update/Staged").path),
      "A rejected download leaves no staging area behind")
  }

  func testSignatureVerificationFailureNeverStages() async throws {
    let (release, downloader, appURL) = makeRelease()
    let installer = RecordingUpdateInstaller()
    let controller = makeController(
      release: release, downloader: downloader, appURL: appURL,
      verifierFailure: UpdateVerificationError.untrustedTeam(
        expected: "TEAM", actual: "other"),
      installer: installer)
    await controller.checkForUpdates()

    guard case .failed(let message) = controller.phase else {
      return XCTFail("Expected failure, got \(controller.phase)")
    }
    XCTAssertTrue(message.contains("team"), message)
    XCTAssertTrue(installer.plans.isEmpty)
  }

  func testSameVersionReportsUpToDate() async throws {
    let (release, downloader, appURL) = makeRelease(version: "0.1.3")
    let installer = RecordingUpdateInstaller()
    let controller = makeController(
      release: release, downloader: downloader, appURL: appURL, installer: installer)
    await controller.checkForUpdates()

    guard case .upToDate = controller.phase else {
      return XCTFail("Expected upToDate, got \(controller.phase)")
    }
    XCTAssertTrue(installer.plans.isEmpty)
  }

  func testSkippedVersionIsNotOfferedAgain() async throws {
    preferences.skippedVersion = "0.2.0"
    let (release, downloader, appURL) = makeRelease()
    let controller = makeController(release: release, downloader: downloader, appURL: appURL)
    await controller.checkForUpdates()

    guard case .upToDate = controller.phase else {
      return XCTFail("Expected upToDate, got \(controller.phase)")
    }
  }

  func testStagedUpdateIsAppliedOnQuitWithoutRelaunch() async throws {
    let (release, downloader, appURL) = makeRelease()
    let installer = RecordingUpdateInstaller()
    let controller = makeController(
      release: release, downloader: downloader, appURL: appURL, installer: installer)
    await controller.checkForUpdates()
    XCTAssertTrue(controller.canRestartToUpdate)

    controller.applyOnTerminate()
    XCTAssertEqual(installer.plans.count, 1)
    XCTAssertEqual(installer.plans.first?.relaunch, false)
  }

  func testDevelopmentBuildLocationDisablesUpdates() async throws {
    let (release, downloader, appURL) = makeRelease()
    let controller = makeController(
      release: release, downloader: downloader, appURL: appURL,
      requiresApplicationsFolder: true)
    controller.start()
    XCTAssertEqual(controller.phase, .disabled(UpdateController.developmentBuildMessage))
    await controller.checkForUpdates()
    XCTAssertEqual(controller.phase, .disabled(UpdateController.developmentBuildMessage))
  }

  func testSkipOfferedReleaseDismissesWithoutInstalling() async throws {
    let (release, downloader, appURL) = makeRelease()
    let installer = RecordingUpdateInstaller()
    let controller = makeController(
      release: release, downloader: downloader, appURL: appURL, installer: installer)
    await controller.checkForUpdates()
    controller.skipOfferedRelease()

    XCTAssertEqual(preferences.skippedVersion, "0.2.0")
    guard case .upToDate = controller.phase else {
      return XCTFail("Expected upToDate, got \(controller.phase)")
    }
    XCTAssertTrue(installer.plans.isEmpty)
  }
}

// MARK: - Test doubles

final class Flag: @unchecked Sendable {
  var value: Bool
  init(_ value: Bool) { self.value = value }
}

struct StubUpdateFeed: UpdateFeedFetching {
  let release: UpdateRelease
  func latestRelease() async throws -> UpdateRelease { release }
}

final class StubUpdateDownloader: UpdateDownloading, @unchecked Sendable {
  let archiveBytes: Data
  let checksumText: String

  init(archiveBytes: Data, checksumText: String) {
    self.archiveBytes = archiveBytes
    self.checksumText = checksumText
  }

  func download(_ asset: UpdateAsset, to destination: URL) async throws {
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try archiveBytes.write(to: destination)
  }

  func data(for asset: UpdateAsset) async throws -> Data { Data(checksumText.utf8) }
}

struct StubUpdateUnarchiver: UpdateUnarchiving {
  let appURL: URL
  func unarchive(_ archiveURL: URL, into directory: URL) throws -> URL { appURL }
}

struct StubUpdateVerifier: UpdateBundleVerifying {
  let failure: Error?
  func verify(appBundle: URL, expectedVersion: UpdateVersion) throws {
    if let failure { throw failure }
  }
}

final class RecordingUpdateInstaller: UpdateInstalling, @unchecked Sendable {
  private(set) var plans: [UpdateInstallPlan] = []
  func install(_ plan: UpdateInstallPlan) throws { plans.append(plan) }
}