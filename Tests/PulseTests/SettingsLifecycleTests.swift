import AppKit
import Carbon.HIToolbox
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

  func testRouteReplacementEndsOnlyTheOutgoingPageEditor() throws {
    let window = NSWindow(
      contentRect: NSRect(x: -16_000, y: -16_000, width: 480, height: 200),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let field = NSTextField()
    let fieldContent = AnyView(RouteTestNativeView(view: field).frame(width: 200, height: 24))
    let multiline = NSTextView()
    let multilineContent = AnyView(RouteTestNativeView(view: multiline).frame(width: 200, height: 60))
    let content = PopoverContentTransition<SettingsDestination, Text>.Container(
      rootView: fieldContent, page: .providers)
    content.frame = NSRect(x: 110, y: 0, width: 370, height: 200)
    let surface = try XCTUnwrap(window.contentView)
    surface.addSubview(content)
    content.layoutSubtreeIfNeeded()

    XCTAssertTrue(window.makeFirstResponder(field))
    let fieldEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    fieldEditor.insertText("Keep the draft", replacementRange: NSRange(location: 0, length: 0))

    content.update(rootView: fieldContent, page: .providers, reduceMotion: false)
    XCTAssertTrue(window.firstResponder === fieldEditor)
    XCTAssertEqual(fieldEditor.string, "Keep the draft")
    content.update(rootView: multilineContent, page: .general, reduceMotion: true)
    XCTAssertNil(field.currentEditor())
    XCTAssertEqual(field.stringValue, "Keep the draft")

    content.layoutSubtreeIfNeeded()
    XCTAssertTrue(window.makeFirstResponder(multiline))
    XCTAssertTrue(window.firstResponder === multiline)
    content.update(rootView: AnyView(Text("Tasks")), page: .tasks, reduceMotion: true)
    XCTAssertFalse(window.firstResponder === multiline)

    let sidebar = NSTextField(frame: NSRect(x: 0, y: 100, width: 100, height: 24))
    surface.addSubview(sidebar)
    XCTAssertTrue(window.makeFirstResponder(sidebar))
    let sidebarEditor = try XCTUnwrap(sidebar.currentEditor())
    content.update(rootView: AnyView(Text("Updates")), page: .updates, reduceMotion: true)
    XCTAssertTrue(window.firstResponder === sidebarEditor)
  }

  func testTodayDraftBelongsToOriginalVaultAndRejectsRetiredField() throws {
    let presentation = TodayTaskPresentation()
    let firstVault = URL(fileURLWithPath: "/fixture/first", isDirectory: true)
    let secondVault = URL(fileURLWithPath: "/fixture/second", isDirectory: true)
    presentation.beginDraft(in: firstVault)
    let firstRequest = try XCTUnwrap(presentation.drafts[firstVault]?.focusRequest)
    presentation.setTitle("Keep this draft", in: firstVault, request: firstRequest)
    XCTAssertTrue(presentation.isEditing(in: firstVault))
    presentation.collapseDraft(in: firstVault)
    presentation.setTitle("Late field event", in: firstVault, request: firstRequest)
    XCTAssertFalse(presentation.isEditing(in: firstVault))
    XCTAssertTrue(presentation.hasUnsavedEdits)
    presentation.beginDraft(in: secondVault)
    XCTAssertEqual(presentation.drafts[secondVault]?.title, "")
    presentation.discardDraft(in: secondVault)
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

  func testSettingsWindowUpdatesNativeBackdropWhenTransparencyChanges() async throws {
    let suite = "PulseSettingsTransparency.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let runtime = PulseRuntimeServices(environment: ["PULSE_DISABLE_LIVE_USAGE": "1"])
    let config = AppConfig(defaults: defaults, loginItemService: runtime.loginItemService)
    let controller = SettingsWindowController(config: config, rootView: Text("Settings"))
    let window = try XCTUnwrap(controller.window)
    window.ignoresMouseEvents = true
    window.setFrameOrigin(NSPoint(x: -16_000, y: -16_000))
    window.orderFront(nil)
    defer { controller.close() }
    func nativeMaterials(in view: NSView) -> [NSVisualEffectView] {
      (view as? NSVisualEffectView).map { [$0] } ?? view.subviews.flatMap(nativeMaterials(in:))
    }
    let content = try XCTUnwrap(window.contentView)
    try await Task.sleep(for: .milliseconds(60))
    content.layoutSubtreeIfNeeded()
    let materials = nativeMaterials(in: content)
    XCTAssertEqual(materials.count, 1)
    XCTAssertEqual(materials.first?.blendingMode, .behindWindow)
    XCTAssertEqual(materials.first?.frame.size, SettingsWindowController.contentSize)

    XCTAssertFalse(window.isOpaque)
    XCTAssertEqual(window.backgroundColor.alphaComponent, 0)
    XCTAssertTrue(window.styleMask.contains(.titled))
    config.setWindowTransparencyPercent(0)
    XCTAssertGreaterThan(window.backgroundColor.alphaComponent, 0.99)
    config.setWindowTransparencyPercent(50)
    XCTAssertEqual(window.backgroundColor.alphaComponent, 0)
    config.setSystemReducesTransparency(true)
    XCTAssertGreaterThan(window.backgroundColor.alphaComponent, 0.99)
    config.setSystemReducesTransparency(false)
    XCTAssertEqual(window.backgroundColor.alphaComponent, 0)
    XCTAssertTrue(controller.window === window)
    XCTAssertEqual(window.contentView?.frame.size, SettingsWindowController.contentSize)
  }

  func testFocusOutlineFollowsTabNavigationAndClearsOnMouseClick() throws {
    let focus = PulsePopoverFocus()
    func keyDown(_ keyCode: Int, characters: String, flags: NSEvent.ModifierFlags = []) throws
      -> NSEvent
    {
      try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
          context: nil, characters: characters, charactersIgnoringModifiers: characters,
          isARepeat: false, keyCode: UInt16(keyCode)))
    }
    let click = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1))

    focus.beginPresentation(with: click)
    XCTAssertFalse(focus.showsKeyboardFocus)
    focus.handleInput(try keyDown(kVK_ANSI_A, characters: "a"))
    XCTAssertFalse(focus.showsKeyboardFocus)
    focus.handleInput(try keyDown(kVK_Tab, characters: "\t", flags: .shift))
    XCTAssertTrue(focus.showsKeyboardFocus)
    focus.handleInput(click)
    XCTAssertFalse(focus.showsKeyboardFocus)
    focus.beginPresentation(with: try keyDown(kVK_ANSI_Grave, characters: "`"))
    XCTAssertTrue(focus.showsKeyboardFocus)
    focus.beginPresentation(with: nil)
    XCTAssertFalse(focus.showsKeyboardFocus)
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

private struct RouteTestNativeView: NSViewRepresentable {
  let view: NSView

  func makeNSView(context: Context) -> NSView { view }
  func updateNSView(_ view: NSView, context: Context) {}
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
