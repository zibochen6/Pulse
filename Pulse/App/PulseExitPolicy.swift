import Foundation

/// Keep destructive app lifecycle decisions independent from view focus. A
/// collapsed draft still counts, and a settings window is an active surface.
struct PulseExitPolicy {
  var popoverOpen: Bool
  var settingsOpen: Bool
  var hasUnsavedEdits: Bool
  var hasPendingWrites: Bool

  var canInstallAutomatically: Bool {
    !popoverOpen && !settingsOpen && !hasUnsavedEdits && !hasPendingWrites
  }
  var requiresDiscardConfirmation: Bool { hasUnsavedEdits }
  var mustWaitForWrites: Bool { hasPendingWrites }
}

@MainActor
final class PulseExitCoordinator {
  enum Action { case quit, restart }
  private(set) var isRequestPending = false
  private let policy: () -> PulseExitPolicy
  private let confirmDiscard: (Action) -> Bool
  private let discard: () -> Void
  private let perform: (Action) -> Void
  private let waitForWrite: () async -> Void

  init(
    policy: @escaping () -> PulseExitPolicy,
    confirmDiscard: @escaping (Action) -> Bool,
    discard: @escaping () -> Void,
    perform: @escaping (Action) -> Void,
    waitForWrite: @escaping () async -> Void = { try? await Task.sleep(for: .milliseconds(100)) }
  ) {
    self.policy = policy
    self.confirmDiscard = confirmDiscard
    self.discard = discard
    self.perform = perform
    self.waitForWrite = waitForWrite
  }

  func request(_ action: Action) async {
    guard !isRequestPending else { return }
    isRequestPending = true
    defer { isRequestPending = false }
    while policy().mustWaitForWrites {
      guard !Task.isCancelled else { return }
      await waitForWrite()
    }
    guard !Task.isCancelled else { return }
    if policy().requiresDiscardConfirmation {
      guard confirmDiscard(action) else { return }
      discard()
    }
    perform(action)
  }
}
