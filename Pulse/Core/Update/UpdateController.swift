import AppKit
import Combine
import Foundation

/// Owns the whole update lifecycle: check, download, verify, stage, install.
///
/// Nothing here installs code that has not passed the checksum and code-signing
/// checks in `UpdateChecksum` / `CodeSigningBundleVerifier`, and the controller
/// only replaces the bundle when the user is not in the middle of editing a task.
@MainActor
final class UpdateController: ObservableObject {
  struct StagedUpdate: Equatable {
    let release: UpdateRelease
    let appBundleURL: URL
    let stagedAt: Date
  }

  enum Phase: Equatable {
    case idle
    case disabled(String)
    case checking
    case upToDate(Date?)
    case available(UpdateRelease)
    case downloading(UpdateRelease)
    case verifying(UpdateRelease)
    case staged(StagedUpdate)
    case installing
    case failed(String)
  }

  static let developmentBuildMessage = "Updates are disabled for development builds."
  static let automaticChecksInterval: TimeInterval = 6 * 60 * 60
  static let launchCheckDelay: TimeInterval = 10

  @Published private(set) var phase: Phase = .idle

  private let feed: any UpdateFeedFetching
  private let downloader: any UpdateDownloading
  private let unarchiver: any UpdateUnarchiving
  private let verifier: any UpdateBundleVerifying
  private let installer: any UpdateInstalling
  private let preferences: UpdatePreferences
  private let currentVersion: UpdateVersion
  private let destinationAppURL: URL
  private let supportDirectory: URL
  private let logsDirectory: URL
  private let requiresApplicationsFolder: Bool
  private let canApplyAutomatically: @MainActor () -> Bool
  private let terminate: @MainActor () -> Void
  private let now: () -> Date
  private let checkInterval: TimeInterval
  private let launchDelay: TimeInterval
  private let fileManager: FileManager

  private var scheduledCheckTask: Task<Void, Never>?
  private var repeatingCheckTask: Task<Void, Never>?
  private var automaticInstallTask: Task<Void, Never>?
  private var isWorking = false

  init(
    feed: any UpdateFeedFetching,
    downloader: any UpdateDownloading,
    unarchiver: any UpdateUnarchiving = DittoUnarchiver(),
    verifier: any UpdateBundleVerifying = CodeSigningBundleVerifier(),
    installer: any UpdateInstalling,
    preferences: UpdatePreferences,
    currentVersion: UpdateVersion = .current(),
    destinationAppURL: URL = Bundle.main.bundleURL,
    supportDirectory: URL = UpdateController.defaultSupportDirectory,
    logsDirectory: URL = UpdateController.defaultLogsDirectory,
    requiresApplicationsFolder: Bool = true,
    canApplyAutomatically: @escaping @MainActor () -> Bool = { true },
    terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) },
    now: @escaping () -> Date = Date.init,
    checkInterval: TimeInterval = UpdateController.automaticChecksInterval,
    launchDelay: TimeInterval = UpdateController.launchCheckDelay,
    fileManager: FileManager = .default
  ) {
    self.feed = feed
    self.downloader = downloader
    self.unarchiver = unarchiver
    self.verifier = verifier
    self.installer = installer
    self.preferences = preferences
    self.currentVersion = currentVersion
    self.destinationAppURL = destinationAppURL
    self.supportDirectory = supportDirectory
    self.logsDirectory = logsDirectory
    self.requiresApplicationsFolder = requiresApplicationsFolder
    self.canApplyAutomatically = canApplyAutomatically
    self.terminate = terminate
    self.now = now
    self.checkInterval = checkInterval
    self.launchDelay = launchDelay
    self.fileManager = fileManager
  }

  static var defaultSupportDirectory: URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    return base.appendingPathComponent("Pulse/Update", isDirectory: true)
  }

  static var defaultLogsDirectory: URL {
    let base =
      FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
    return base.appendingPathComponent("Logs/Pulse", isDirectory: true)
  }

  // MARK: - Presentation

  var currentVersionText: String {
    guard let build = currentVersion.build else { return currentVersion.description }
    return "\(currentVersion.description) (\(build))"
  }

  var isBusy: Bool {
    switch phase {
    case .checking, .downloading, .verifying, .installing: true
    default: false
    }
  }

  var canRestartToUpdate: Bool {
    if case .staged = phase { return true }
    return false
  }

  var stagedRelease: UpdateRelease? {
    if case .staged(let staged) = phase { return staged.release }
    return nil
  }

  var offeredRelease: UpdateRelease? {
    switch phase {
    case .available(let release), .downloading(let release), .verifying(let release): release
    case .staged(let staged): staged.release
    default: nil
    }
  }

  var statusText: String {
    switch phase {
    case .idle:
      "Updates are checked automatically."
    case .disabled(let reason):
      reason
    case .checking:
      "Checking for updates…"
    case .upToDate(let date):
      if let date {
        "Pulse \(currentVersionText) is up to date. Last checked "
          + date.formatted(date: .abbreviated, time: .shortened) + "."
      } else {
        "Pulse \(currentVersionText) is up to date."
      }
    case .available(let release):
      "Pulse \(release.version) is available."
    case .downloading(let release):
      "Downloading Pulse \(release.version)…"
    case .verifying(let release):
      "Verifying Pulse \(release.version)…"
    case .staged(let staged):
      "Pulse \(staged.release.version) is ready. Restart to update."
    case .installing:
      "Installing the update and restarting…"
    case .failed(let message):
      message
    }
  }

  var automaticChecksEnabled: Bool {
    get { preferences.automaticallyChecks }
    set {
      preferences.automaticallyChecks = newValue
      if newValue {
        scheduleNextCheck(after: 0)
        startRepeatingChecks()
      } else {
        scheduledCheckTask?.cancel()
        repeatingCheckTask?.cancel()
      }
    }
  }

  /// Only an app installed in a user-writable location can replace itself. A
  /// development build (DerivedData, a mounted image, a read-only volume) still
  /// shows the section, but never downloads or installs.
  var isUpdateSupported: Bool {
    let destination = destinationAppURL.standardizedFileURL
    let destinationPath = destination.path
    if requiresApplicationsFolder && !destinationPath.hasPrefix("/Applications/") {
      return false
    }
    let parent = destination.deletingLastPathComponent().path
    return fileManager.isWritableFile(atPath: parent)
      && fileManager.isWritableFile(atPath: destinationPath)
  }

  // MARK: - Lifecycle

  /// Called once by the app delegate after launch. A fresh run starts from a
  /// clean staging area; a leftover archive from a crashed install is discarded
  /// rather than installed without context.
  func start() {
    removeStagingRoot()
    guard isUpdateSupported else {
      phase = .disabled(Self.developmentBuildMessage)
      return
    }
    phase = .idle
    guard preferences.automaticallyChecks else { return }
    scheduleNextCheck(after: launchDelay)
    startRepeatingChecks()
  }

  // MARK: - Checking

  func checkForUpdates(userInitiated: Bool = true) async {
    guard !isWorking else { return }
    guard isUpdateSupported else {
      phase = .disabled(Self.developmentBuildMessage)
      return
    }
    if !userInitiated && !preferences.automaticallyChecks { return }
    isWorking = true
    defer { isWorking = false }
    phase = .checking
    do {
      let release = try await feed.latestRelease()
      let checkedAt = now()
      preferences.lastCheckDate = checkedAt
      if preferences.skippedVersion == release.version.description {
        phase = .upToDate(checkedAt)
        return
      }
      guard release.version > currentVersion else {
        phase = .upToDate(checkedAt)
        return
      }
      phase = .available(release)
      // A manual check always continues into the download; an automatic one
      // respects the user's "check automatically" preference.
      if userInitiated || preferences.automaticallyChecks {
        await stage(release)
      }
    } catch {
      phase = .failed(Self.message(for: error))
    }
  }

  /// Downloads, authenticates and unpacks the release, then either restarts into
  /// it or waits for a safe moment.
  func stage(_ release: UpdateRelease) async {
    phase = .downloading(release)
    let stagingDirectory = stagingDirectory(for: release)
    do {
      try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
      let archiveURL = stagingDirectory.appendingPathComponent(release.archive.name)
      try await downloader.download(release.archive, to: archiveURL)
      let checksumData = try await downloader.data(for: release.checksum)
      guard let checksumText = String(data: checksumData, encoding: .utf8) else {
        throw UpdateVerificationError.checksumMalformed
      }
      let publishedHex = try UpdateChecksum.parse(checksumText)
      if let metadataHex = release.archive.sha256, metadataHex != publishedHex {
        throw UpdateVerificationError.checksumMismatch(
          expected: metadataHex, actual: publishedHex)
      }
      try UpdateChecksum.verify(fileAt: archiveURL, matchesPublishedHex: publishedHex)

      phase = .verifying(release)
      let expandedURL = stagingDirectory.appendingPathComponent("Expanded", isDirectory: true)
      let appBundleURL = try unarchiver.unarchive(archiveURL, into: expandedURL)
      try verifier.verify(appBundle: appBundleURL, expectedVersion: release.version)

      try? fileManager.removeItem(at: archiveURL)
      phase = .staged(
        StagedUpdate(release: release, appBundleURL: appBundleURL, stagedAt: now()))
      if canApplyAutomatically() {
        restartToUpdate()
      } else {
        scheduleAutomaticInstallWhenIdle()
      }
    } catch {
      // A rejected download must not leave half-verified bytes behind either.
      removeStagingRoot()
      phase = .failed(Self.message(for: error))
    }
  }

  // MARK: - Installing

  /// Installs the staged update and relaunches Pulse into it.
  func restartToUpdate() {
    guard case .staged(let staged) = phase else { return }
    automaticInstallTask?.cancel()
    do {
      try installer.install(installPlan(for: staged, relaunch: true))
      phase = .installing
      terminate()
    } catch {
      phase = .failed(Self.message(for: error))
    }
  }

  /// Last chance: if an update was staged but never installed, apply it while
  /// Pulse is quitting. It does not relaunch, because the user chose to quit.
  func applyOnTerminate() {
    guard case .staged(let staged) = phase else { return }
    _ = try? installer.install(installPlan(for: staged, relaunch: false))
  }

  func skipOfferedRelease() {
    guard let release = offeredRelease else { return }
    preferences.skippedVersion = release.version.description
    automaticInstallTask?.cancel()
    phase = .upToDate(now())
  }

  func dismissFailure() {
    if case .failed = phase { phase = .idle }
  }

  private func installPlan(for staged: StagedUpdate, relaunch: Bool) -> UpdateInstallPlan {
    UpdateInstallPlan(
      stagedAppPath: staged.appBundleURL.path,
      destinationAppPath: destinationAppURL.path,
      backupAppPath: backupDirectory
        .appendingPathComponent(
          "Pulse-\(currentVersion.description)-\(currentVersion.build.map(String.init) ?? "0").app"
        ).path,
      logPath: logsDirectory.appendingPathComponent("update.log").path,
      stagingRootPath: stagingRoot.path,
      oldProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
      relaunch: relaunch
    )
  }

  private func scheduleAutomaticInstallWhenIdle() {
    automaticInstallTask?.cancel()
    automaticInstallTask = Task { [weak self] in
      // Poll for a quiet moment: the popover closed and no task draft open.
      for _ in 0..<400 {
        try? await Task.sleep(for: .seconds(3))
        if Task.isCancelled { return }
        guard let self, case .staged = self.phase else { return }
        if self.canApplyAutomatically() {
          self.restartToUpdate()
          return
        }
      }
    }
  }

  private func scheduleNextCheck(after delay: TimeInterval) {
    scheduledCheckTask?.cancel()
    scheduledCheckTask = Task { [weak self] in
      if delay > 0 {
        try? await Task.sleep(for: .seconds(delay))
      }
      if Task.isCancelled { return }
      await self?.checkForUpdates(userInitiated: false)
    }
  }

  private func startRepeatingChecks() {
    repeatingCheckTask?.cancel()
    let interval = checkInterval
    repeatingCheckTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(interval))
        if Task.isCancelled { return }
        await self?.checkForUpdates(userInitiated: false)
      }
    }
  }

  // MARK: - Files

  private var stagingRoot: URL {
    supportDirectory.appendingPathComponent("Staged", isDirectory: true)
  }

  private var backupDirectory: URL {
    supportDirectory.deletingLastPathComponent()
      .appendingPathComponent("Backups", isDirectory: true)
  }

  private func stagingDirectory(for release: UpdateRelease) -> URL {
    stagingRoot.appendingPathComponent(release.version.description, isDirectory: true)
  }

  private func removeStagingRoot() {
    try? fileManager.removeItem(at: stagingRoot)
  }

  private static func message(for error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  }
}