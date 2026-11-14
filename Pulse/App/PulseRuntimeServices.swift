import Foundation

/// Test and demo hosts must stay isolated even when a manual control requests
/// refresh, credential changes, login registration, or an update.
@MainActor
struct PulseRuntimeServices {
  let permitsLiveAccess: Bool

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    permitsLiveAccess = environment["PULSE_DISABLE_LIVE_USAGE"] != "1"
  }

  var secretStore: any SecretStoring {
    permitsLiveAccess ? KeychainSecretStore() : InactiveRuntimeServices()
  }

  var loginItemService: any LoginItemManaging {
    permitsLiveAccess ? SystemLoginItemService() : InactiveRuntimeLoginItemService()
  }

  func usageProvider(_ live: @autoclosure () -> any UsageProviding) -> any UsageProviding {
    permitsLiveAccess ? live() : InactiveRuntimeServices()
  }

  var updateFeed: any UpdateFeedFetching {
    permitsLiveAccess ? GitHubUpdateFeed() : InactiveRuntimeServices()
  }

  var updateDownloader: any UpdateDownloading {
    permitsLiveAccess ? URLSessionUpdateDownloader() : InactiveRuntimeServices()
  }

  func updateInstaller(scriptDirectory: URL) -> any UpdateInstalling {
    permitsLiveAccess
      ? DetachedScriptInstaller(scriptDirectory: scriptDirectory) : InactiveRuntimeServices()
  }
}

private struct InactiveRuntimeServices: SecretStoring, UsageProviding, UpdateFeedFetching,
  UpdateDownloading, UpdateInstalling
{
  func read(account: String) throws -> String? { nil }
  func save(_ secret: String, account: String) throws { throw CancellationError() }
  func delete(account: String) throws { throw CancellationError() }

  func fetch() async throws -> UsageSnapshot {
    UsageSnapshot(providerID: "inactive", fetchedAt: .now, metrics: [])
  }

  func latestRelease() async throws -> UpdateRelease { throw CancellationError() }
  func download(_ asset: UpdateAsset, to destination: URL) async throws {
    throw CancellationError()
  }
  func data(for asset: UpdateAsset) async throws -> Data { throw CancellationError() }
  func install(_ plan: UpdateInstallPlan) throws { throw CancellationError() }

}

private struct InactiveRuntimeLoginItemService: LoginItemManaging {
  var status: LoginItemStatus { .notRegistered }
  func setEnabled(_ enabled: Bool) throws { throw CancellationError() }
}
