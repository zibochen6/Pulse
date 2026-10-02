import AppKit

enum PopoverPointerRegion {
  case statusButton
  case content
}

struct PopoverPointerPresence {
  let statusButton: Bool
  let content: Bool
  let popoverWindow: Bool

  var isInside: Bool { statusButton || content || popoverWindow }
}

enum PopoverHoverState: Equatable {
  case closed
  case opening
  case interactive
  case pendingClose
  case closing
}

/// Owns hover dismissal. AppKit still handles immediate transient outside clicks.
@MainActor
final class PopoverHoverController {
  private let openingNanoseconds: UInt64
  private let closeDelayNanoseconds: UInt64
  private let reconciliationNanoseconds: UInt64
  private let pointerPresence: @MainActor () -> PopoverPointerPresence
  private let close: @MainActor () -> Void
  private var overStatusButton = false
  private var overContent = false
  private var overPopoverWindow = false
  private var openingProtectionFinished = false
  private var presentationFinished = false
  private var dismissalSuspended = false
  private var openingTask: Task<Void, Never>?
  private var pendingCloseTask: Task<Void, Never>?
  private var reconciliationTask: Task<Void, Never>?

  private(set) var state: PopoverHoverState = .closed

  init(
    openingNanoseconds: UInt64 = 300_000_000,
    closeDelayNanoseconds: UInt64 = 180_000_000,
    reconciliationNanoseconds: UInt64 = 50_000_000,
    pointerPresence: @escaping @MainActor () -> PopoverPointerPresence,
    close: @escaping @MainActor () -> Void
  ) {
    self.openingNanoseconds = openingNanoseconds
    self.closeDelayNanoseconds = closeDelayNanoseconds
    self.reconciliationNanoseconds = reconciliationNanoseconds
    self.pointerPresence = pointerPresence
    self.close = close
  }

  func beginOpening() {
    guard state != .closing else { return }
    reset()
    state = .opening
    startReconciliation()
    openingTask = Task { [weak self, openingNanoseconds] in
      do {
        try await Task.sleep(nanoseconds: openingNanoseconds)
      } catch {
        return
      }
      guard let self, !Task.isCancelled, self.state == .opening else { return }
      self.openingTask = nil
      self.openingProtectionFinished = true
      self.finishOpeningIfReady()
    }
  }

  /// AppKit's show animation may last longer than the minimum click protection.
  func presentationDidShow() {
    guard state == .opening else { return }
    presentationFinished = true
    finishOpeningIfReady()
  }

  /// Seeds tracked regions after `show`; events during Opening may still revise them.
  func synchronize(statusButton: Bool, content: Bool, popoverWindow: Bool = false) {
    guard state != .closed, state != .closing else { return }
    overStatusButton = statusButton
    overContent = content
    overPopoverWindow = popoverWindow
    updateCloseSchedule()
  }

  func entered(_ region: PopoverPointerRegion) {
    setInside(true, region: region)
  }

  func exited(_ region: PopoverPointerRegion) {
    setInside(false, region: region)
  }

  /// Editing suppresses hover departure only; AppKit outside clicks still dismiss.
  func setDismissalSuspended(_ suspended: Bool) {
    guard state != .closing else { return }
    dismissalSuspended = suspended
    guard state != .closed, state != .opening else { return }
    if suspended {
      pendingCloseTask?.cancel()
      pendingCloseTask = nil
      state = .interactive
    } else {
      let presence = pointerPresence()
      overStatusButton = presence.statusButton
      overContent = presence.content
      overPopoverWindow = presence.popoverWindow
      updateCloseSchedule()
    }
  }

  /// Called by both requested and native transient dismissal. Navigation resets
  /// only after AppKit finishes closing; late tracking events cannot reopen it.
  func beginClosing() {
    reset()
    state = .closing
  }

  func requestClose() {
    guard state != .closed, state != .closing else { return }
    beginClosing()
    close()
  }

  func reset() {
    openingTask?.cancel()
    openingTask = nil
    pendingCloseTask?.cancel()
    pendingCloseTask = nil
    reconciliationTask?.cancel()
    reconciliationTask = nil
    overStatusButton = false
    overContent = false
    overPopoverWindow = false
    openingProtectionFinished = false
    presentationFinished = false
    dismissalSuspended = false
    state = .closed
  }

  private func setInside(_ inside: Bool, region: PopoverPointerRegion) {
    guard state != .closed, state != .closing else { return }
    switch region {
    case .statusButton:
      overStatusButton = inside
    case .content:
      overContent = inside
    }
    overPopoverWindow = pointerPresence().popoverWindow
    updateCloseSchedule()
  }

  private func finishOpeningIfReady() {
    guard state == .opening, openingProtectionFinished, presentationFinished else { return }
    // Entry/exit events around the click can be stale or missing. The current
    // geometry, including the popover arrow, is authoritative at this boundary.
    let presence = pointerPresence()
    overStatusButton = presence.statusButton
    overContent = presence.content
    overPopoverWindow = presence.popoverWindow
    state = .interactive
    updateCloseSchedule()
  }

  private func startReconciliation() {
    reconciliationTask = Task { [weak self, reconciliationNanoseconds] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: reconciliationNanoseconds)
        } catch {
          return
        }
        guard let self, !Task.isCancelled, self.state != .closed, self.state != .closing else {
          return
        }
        self.reconcilePointerPresence()
      }
    }
  }

  private func reconcilePointerPresence() {
    let presence = pointerPresence()
    let didChange =
      overStatusButton != presence.statusButton || overContent != presence.content
      || overPopoverWindow != presence.popoverWindow
    guard didChange else { return }

    // AppKit can omit an exit while a SwiftUI hierarchy changes. Correct the
    // tracked state from geometry without restarting an existing close timer.
    overStatusButton = presence.statusButton
    overContent = presence.content
    overPopoverWindow = presence.popoverWindow
    updateCloseSchedule()
  }

  private func updateCloseSchedule() {
    guard state == .interactive || state == .pendingClose else { return }
    if dismissalSuspended || overStatusButton || overContent || overPopoverWindow {
      pendingCloseTask?.cancel()
      pendingCloseTask = nil
      state = .interactive
    } else {
      schedulePendingClose()
    }
  }

  private func schedulePendingClose() {
    // Duplicate exits/reconciliation must not restart the grace interval.
    guard pendingCloseTask == nil else { return }
    state = .pendingClose
    pendingCloseTask = Task { [weak self, closeDelayNanoseconds] in
      do {
        try await Task.sleep(nanoseconds: closeDelayNanoseconds)
      } catch {
        return
      }
      guard let self, !Task.isCancelled, self.state == .pendingClose else { return }
      self.pendingCloseTask = nil
      let presence = self.pointerPresence()
      if presence.isInside {
        self.synchronize(
          statusButton: presence.statusButton, content: presence.content,
          popoverWindow: presence.popoverWindow)
      } else {
        self.requestClose()
      }
    }
  }
}

/// NSTrackingArea sends AppKit mouse events to its owner.
@MainActor
final class PopoverPointerTrackingOwner: NSObject {
  private let onEnter: @MainActor () -> Void
  private let onExit: @MainActor () -> Void

  init(onEnter: @escaping @MainActor () -> Void, onExit: @escaping @MainActor () -> Void) {
    self.onEnter = onEnter
    self.onExit = onExit
  }

  @objc(mouseEntered:) func mouseEntered(with event: NSEvent) {
    onEnter()
  }

  @objc(mouseExited:) func mouseExited(with event: NSEvent) {
    onExit()
  }
}
