import AppKit
import SwiftUI
import XCTest

@testable import Pulse

@MainActor
final class SettingsLifecycleTests: XCTestCase {
  func testDisabledRuntimeNeverConstructsOrRefreshesLiveProvider() async {
    let runtime = PulseRuntimeServices(environment: ["PULSE_DISABLE_LIVE_USAGE": "1"])
    var constructedLiveProvider = false
    func liveProvider() -> any UsageProviding {
      constructedLiveProvider = true
      return InactiveSettingsProvider()
    }
    let usage = UsageController(provider: runtime.usageProvider(liveProvider()))
    await usage.requestRefresh().value
    await usage.credentialsDidChange().value
    await usage.refreshIfStale(maxAge: 0)?.value
    XCTAssertFalse(constructedLiveProvider)
    guard case .unavailable = usage.state else {
      return XCTFail("An isolated manual refresh must never display account data")
    }
    XCTAssertTrue(PulseRuntimeServices(environment: [:]).permitsLiveAccess)
  }

  func testDisabledRuntimeCannotReadOrModifyKeychainOrLoginRegistration() throws {
    let runtime = PulseRuntimeServices(environment: ["PULSE_DISABLE_LIVE_USAGE": "1"])
    let store = runtime.secretStore
    XCTAssertNil(try store.read(account: DeepSeekConfiguration.keychainAccount))
    XCTAssertThrowsError(try store.save("sample", account: DeepSeekConfiguration.keychainAccount))
    XCTAssertThrowsError(try store.delete(account: DeepSeekConfiguration.keychainAccount))
    XCTAssertEqual(runtime.loginItemService.status, .notRegistered)
    XCTAssertThrowsError(try runtime.loginItemService.setEnabled(true))
    XCTAssertFalse(runtime.updateFeed is GitHubUpdateFeed)
    XCTAssertFalse(runtime.updateDownloader is URLSessionUpdateDownloader)
    XCTAssertFalse(
      runtime.updateInstaller(scriptDirectory: FileManager.default.temporaryDirectory)
        is DetachedScriptInstaller)
  }

  func testPendingCredentialReadCannotOverrideNewSave() async {
    let began = expectation(description: "Background credential read started")
    let store = PausedCredentialRead(began: began)
    let configuration = DeepSeekConfiguration(secretStore: store)
    let read = Task { await configuration.refreshInBackground() }
    await fulfillment(of: [began], timeout: 2)

    XCTAssertTrue(configuration.save(apiKey: "synthetic-new-key"))
    store.resume.signal()
    await read.value

    XCTAssertTrue(configuration.hasAPIKey)
    XCTAssertNil(configuration.errorMessage)
  }

  func testStoredInvalidCredentialIsNotConnected() {
    XCTAssertEqual(
      ProviderConnectionState.resolve(hasCredential: false, state: .loading), .notConnected)
    XCTAssertEqual(
      ProviderConnectionState.resolve(hasCredential: true, state: .loading), .verifying)
    XCTAssertEqual(
      ProviderConnectionState.resolve(hasCredential: true, state: .failure("Invalid key")),
      .needsAttention("Invalid key"))
    let snapshot = UsageSnapshot(
      providerID: "deepseek", fetchedAt: .now,
      metrics: [.balance(amount: 0, currency: "CNY")])
    XCTAssertEqual(
      ProviderConnectionState.resolve(hasCredential: true, state: .success(snapshot)), .connected)
    XCTAssertEqual(
      ProviderConnectionState.resolve(hasCredential: false, state: .success(snapshot)),
      .notConnected,
      "Removing the key cannot leave a stale success badge")
    XCTAssertEqual(
      ProviderConnectionState.resolve(
        hasCredential: true, configurationError: "Keychain error", state: .success(snapshot)),
      .needsAttention("Keychain error"))
  }

  func testSettingsRoutesAndPreservesIndependentDrafts() {
    let presentation = SettingsPresentation()
    presentation.open(.providers, provider: .deepSeek)
    XCTAssertEqual(presentation.destination, .providers)
    XCTAssertTrue(presentation.expandedProviders.contains(.deepSeek))
    presentation.setDraft("unsaved example", for: .deepSeek)
    let editorID = presentation.editorID(for: .deepSeek)
    presentation.open(.general)
    presentation.open()
    XCTAssertEqual(presentation.destination, .general)
    XCTAssertTrue(presentation.hasUnsavedEdits)
    XCTAssertEqual(presentation.draft(for: .deepSeek), "unsaved example")
    presentation.open(.providers, provider: .vip)
    presentation.setDraft("other draft", for: .vip)
    presentation.finishEditing(.vip)
    XCTAssertEqual(presentation.editorID(for: .deepSeek), editorID)
    XCTAssertEqual(presentation.draft(for: .deepSeek), "unsaved example")
    XCTAssertNil(presentation.editorID(for: .vip))
    presentation.discardAllDrafts()
    XCTAssertFalse(presentation.hasUnsavedEdits)
  }

  func testTodayDraftBelongsToOriginalVaultAndRejectsRetiredField() throws {
    let presentation = TodayTaskPresentation()
    let firstVault = URL(fileURLWithPath: "/fixture/first", isDirectory: true)
    let secondVault = URL(fileURLWithPath: "/fixture/second", isDirectory: true)
    XCTAssertFalse(presentation.showsLocalTasks)
    presentation.beginDraft(in: firstVault)
    let firstRequest = try XCTUnwrap(presentation.drafts[firstVault]?.focusRequest)
    presentation.setTitle("Keep this draft", in: firstVault, request: firstRequest)
    XCTAssertTrue(presentation.isEditing(in: firstVault))
    presentation.collapseDraft(in: firstVault)
    presentation.setTitle("Late field event", in: firstVault, request: firstRequest)
    XCTAssertFalse(presentation.isEditing(in: firstVault))
    XCTAssertTrue(presentation.hasUnsavedEdits)
    presentation.showsLocalTasks = true
    presentation.beginDraft(in: secondVault)
    XCTAssertEqual(presentation.drafts[secondVault]?.title, "")
    presentation.discardDraft(in: secondVault)
    presentation.showsLocalTasks = false
    presentation.beginDraft(in: firstVault)
    presentation.setTitle("Late field after reopen", in: firstVault, request: firstRequest)
    XCTAssertEqual(presentation.drafts[firstVault]?.title, "Keep this draft")
    presentation.discardAllDrafts()
    presentation.beginDraft(in: firstVault)
    presentation.setTitle("Retired field event", in: firstVault, request: firstRequest)
    XCTAssertEqual(presentation.drafts[firstVault]?.title, "")
    XCTAssertFalse(presentation.hasUnsavedEdits)
  }

  func testWindowReusesInstanceAndCloseKeepsSession() {
    let presentation = SettingsPresentation()
    presentation.setDraft("kept only in memory", for: .deepSeek)
    let controller = SettingsWindowController(rootView: Text("Test settings"))
    let original = controller.window
    controller.open()
    controller.open()
    XCTAssertTrue(controller.window === original)
    XCTAssertTrue(controller.isOpen)
    XCTAssertEqual(controller.window?.contentView?.frame.size, SettingsWindowController.contentSize)
    controller.close()
    XCTAssertFalse(controller.isOpen)
    XCTAssertTrue(presentation.hasUnsavedEdits)
  }

  func testAutomaticInstallRequiresAllSurfacesAndDraftsIdle() {
    let idle = PulseExitPolicy(
      popoverOpen: false, settingsOpen: false,
      hasUnsavedEdits: false, hasPendingWrites: false)
    XCTAssertTrue(idle.canInstallAutomatically)
    var state = idle
    state.settingsOpen = true
    XCTAssertFalse(state.canInstallAutomatically)
    state = idle
    state.popoverOpen = true
    XCTAssertFalse(state.canInstallAutomatically)
    state = idle
    state.hasUnsavedEdits = true
    XCTAssertFalse(state.canInstallAutomatically)
    state = idle
    state.hasPendingWrites = true
    XCTAssertFalse(state.canInstallAutomatically)
  }

  func testCancellingRestartNeverCallsDiscardOrInstaller() async {
    var discarded = false
    var performed = false
    let coordinator = PulseExitCoordinator(
      policy: {
        PulseExitPolicy(
          popoverOpen: false, settingsOpen: true,
          hasUnsavedEdits: true, hasPendingWrites: false)
      },
      confirmDiscard: { _ in false }, discard: { discarded = true },
      perform: { _ in performed = true })
    await coordinator.request(.restart)
    XCTAssertFalse(discarded)
    XCTAssertFalse(performed)
    XCTAssertFalse(coordinator.isRequestPending)
  }

  func testRestartWaitsForWriteThenConfirmsBeforeInstalling() async {
    var state = PulseExitPolicy(
      popoverOpen: false, settingsOpen: true,
      hasUnsavedEdits: true, hasPendingWrites: true)
    var events: [String] = []
    let coordinator = PulseExitCoordinator(
      policy: { state },
      confirmDiscard: { _ in
        events.append("confirm")
        return true
      },
      discard: {
        events.append("discard")
        state.hasUnsavedEdits = false
      },
      perform: { _ in events.append("install") },
      waitForWrite: {
        events.append("write finished")
        state.hasPendingWrites = false
      })
    await coordinator.request(.restart)
    XCTAssertEqual(events, ["write finished", "confirm", "discard", "install"])
  }
}

private struct PausedCredentialRead: SecretStoring {
  let began: XCTestExpectation
  let resume = DispatchSemaphore(value: 0)

  func read(account: String) throws -> String? {
    XCTAssertFalse(Thread.isMainThread)
    began.fulfill()
    _ = resume.wait(timeout: .now() + 5)
    return nil
  }

  func save(_ secret: String, account: String) throws {}
  func delete(account: String) throws {}
}
