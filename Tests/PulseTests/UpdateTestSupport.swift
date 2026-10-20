import Foundation

@testable import Pulse

/// Update fakes for render tests: the popover and Settings need a controller,
/// but rendering must never reach the network or replace anything.
struct InactiveUpdateFeed: UpdateFeedFetching {
  func latestRelease() async throws -> UpdateRelease {
    throw UpdateFeedError.unsupportedResponse
  }
}

struct InactiveUpdateDownloader: UpdateDownloading {
  func download(_ asset: UpdateAsset, to destination: URL) async throws {
    throw UpdateDownloadError.emptyDownload
  }

  func data(for asset: UpdateAsset) async throws -> Data {
    throw UpdateDownloadError.emptyDownload
  }
}

struct InactiveUpdateInstaller: UpdateInstalling {
  func install(_ plan: UpdateInstallPlan) throws {}
}

@MainActor
func makeInactiveUpdateController(
  defaults: UserDefaults,
  currentVersion: UpdateVersion = UpdateVersion(major: 0, minor: 1, patch: 3, build: 7)
) -> UpdateController {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "PulseInactiveUpdate-\(UUID().uuidString)", isDirectory: true)
  return UpdateController(
    feed: InactiveUpdateFeed(),
    downloader: InactiveUpdateDownloader(),
    installer: InactiveUpdateInstaller(),
    preferences: UpdatePreferences(defaults: defaults),
    currentVersion: currentVersion,
    destinationAppURL: directory.appendingPathComponent("Pulse.app"),
    supportDirectory: directory.appendingPathComponent("Update", isDirectory: true),
    logsDirectory: directory.appendingPathComponent("Logs", isDirectory: true),
    requiresApplicationsFolder: false
  )
}