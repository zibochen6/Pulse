import Foundation
import XCTest
@testable import Pulse

@MainActor
final class AppConfigTests: XCTestCase {
  func testPreferencesDefaultOffAndPersistAcrossInstances() throws {
    let (defaults, suiteName) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let service = FakeLoginItemService()

    let initial = AppConfig(defaults: defaults, loginItemService: service)
    XCTAssertFalse(initial.launchAtLoginRequested)
    XCTAssertFalse(initial.showMenuBarLabel)

    initial.setShowMenuBarLabel(true)
    initial.setLaunchAtLogin(true)

    let restored = AppConfig(defaults: defaults, loginItemService: service)
    XCTAssertTrue(restored.showMenuBarLabel)
    XCTAssertTrue(restored.launchAtLoginRequested)
    XCTAssertEqual(service.requests, [true])
    XCTAssertEqual(restored.loginItemStatus, .enabled)
  }

  func testApprovalStatusIsDistinctFromRequestedPreference() throws {
    let (defaults, suiteName) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let service = FakeLoginItemService(status: .requiresApproval)
    let config = AppConfig(defaults: defaults, loginItemService: service)

    config.setLaunchAtLogin(true)

    XCTAssertTrue(config.launchAtLoginRequested)
    XCTAssertEqual(config.loginItemStatus, .requiresApproval)
    XCTAssertNil(config.loginItemError)
  }

  func testRegistrationFailureDoesNotReportEnabled() throws {
    let (defaults, suiteName) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let service = FakeLoginItemService(failure: TestError.registrationFailed)
    let config = AppConfig(defaults: defaults, loginItemService: service)

    config.setLaunchAtLogin(true)

    XCTAssertTrue(config.launchAtLoginRequested)
    XCTAssertEqual(config.loginItemStatus, .notRegistered)
    XCTAssertNotNil(config.loginItemError)
  }

  func testDisablingUnregistersLoginItem() throws {
    let (defaults, suiteName) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let service = FakeLoginItemService(status: .enabled)
    let config = AppConfig(defaults: defaults, loginItemService: service)

    config.setLaunchAtLogin(false)

    XCTAssertEqual(service.requests, [false])
    XCTAssertEqual(config.loginItemStatus, .notRegistered)
  }

  func testAlreadyEnabledExternallyDoesNotRegisterAgain() throws {
    let (defaults, suiteName) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let service = FakeLoginItemService(status: .enabled)
    let config = AppConfig(defaults: defaults, loginItemService: service)

    XCTAssertFalse(config.launchAtLoginRequested)
    config.setLaunchAtLogin(true)

    XCTAssertTrue(config.launchAtLoginRequested)
    XCTAssertEqual(config.loginItemStatus, .enabled)
    XCTAssertTrue(service.requests.isEmpty)
    XCTAssertNil(config.loginItemError)
  }

  func testRefreshClearsResolvedRegistrationError() throws {
    let (defaults, suiteName) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let service = FakeLoginItemService(failure: TestError.registrationFailed)
    let config = AppConfig(defaults: defaults, loginItemService: service)

    config.setLaunchAtLogin(true)
    XCTAssertNotNil(config.loginItemError)

    service.status = .enabled
    config.refreshLoginItemStatus()

    XCTAssertEqual(config.loginItemStatus, .enabled)
    XCTAssertNil(config.loginItemError)
  }

  private func makeDefaults() throws -> (UserDefaults, String) {
    let suiteName = "PulseTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw TestError.defaultsUnavailable
    }
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
  }
}

@MainActor
private final class FakeLoginItemService: LoginItemManaging {
  var status: LoginItemStatus
  var requests: [Bool] = []
  var failure: Error?

  init(status: LoginItemStatus = .notRegistered, failure: Error? = nil) {
    self.status = status
    self.failure = failure
  }

  func setEnabled(_ enabled: Bool) throws {
    requests.append(enabled)
    if let failure { throw failure }
    if status != .requiresApproval { status = enabled ? .enabled : .notRegistered }
  }
}

private enum TestError: Error {
  case registrationFailed
  case defaultsUnavailable
}
