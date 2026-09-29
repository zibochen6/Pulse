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
}

/// Owns hover dismissal. AppKit still handles immediate transient outside clicks.
@MainActor
final class PopoverHoverController {
  private let openingNanoseconds: UInt64
  private let closeDelayNanoseconds: UInt64
  private let pointerPresence: @MainActor () -> PopoverPointerPresence
  private let close: @MainActor () -> Void
  private var overStatusButton = false
  private var overContent = false
  private var openingTask: Task<Void, Never>?
  private var pendingCloseTask: Task<Void, Never>?

  private(set) var state: PopoverHoverState = .closed

  init(
    openingNanoseconds: UInt64 = 1_000_000_000,
    closeDelayNanoseconds: UInt64 = 400_000_000,
    pointerPresence: @escaping @MainActor () -> PopoverPointerPresence,
    close: @escaping @MainActor () -> Void
  ) {
    self.openingNanoseconds = openingNanoseconds
    self.closeDelayNanoseconds = closeDelayNanoseconds
    self.pointerPresence = pointerPresence
    self.close = close
  }

  func beginOpening() {
    reset()
    state = .opening
    openingTask = Task { [weak self, openingNanoseconds] in
      do {
        try await Task.sleep(nanoseconds: openingNanoseconds)
      } catch {
        return
      }
      guard let self, !Task.isCancelled, self.state == .opening else { return }
      self.openingTask = nil
      self.finishOpening()
    }
  }

  /// Seeds tracked regions after `show`; events during Opening may still revise them.
  func synchronize(statusButton: Bool, content: Bool) {
    guard state != .closed else { return }
    overStatusButton = statusButton
    overContent = content
    updateCloseSchedule()
  }

  func entered(_ region: PopoverPointerRegion) {
    setInside(true, region: region)
  }

  func exited(_ region: PopoverPointerRegion) {
    setInside(false, region: region)
  }

  func reset() {
    openingTask?.cancel()
    openingTask = nil
    pendingCloseTask?.cancel()
    pendingCloseTask = nil
    overStatusButton = false
    overContent = false
    state = .closed
  }

  private func setInside(_ inside: Bool, region: PopoverPointerRegion) {
    guard state != .closed else { return }
    switch region {
    case .statusButton:
      overStatusButton = inside
    case .content:
      overContent = inside
    }
    updateCloseSchedule()
  }

  private func finishOpening() {
    // Entry/exit events around the click can be stale or missing. The current
    // geometry, including the popover arrow, is authoritative at this boundary.
    let presence = pointerPresence()
    overStatusButton = presence.statusButton
    // Do not latch window-only hover as a tracked content entry: the arrow has
    // no matching content-exit event. The pending check polls its geometry.
    overContent = presence.content
    state = .interactive
    updateCloseSchedule()
  }

  private func updateCloseSchedule() {
    guard state != .closed, state != .opening else { return }
    if overStatusButton || overContent {
      pendingCloseTask?.cancel()
      pendingCloseTask = nil
      state = .interactive
    } else {
      schedulePendingClose()
    }
  }

  private func schedulePendingClose() {
    pendingCloseTask?.cancel()
    state = .pendingClose
    pendingCloseTask = Task { [weak self, closeDelayNanoseconds] in
      do {
        try await Task.sleep(nanoseconds: closeDelayNanoseconds)
      } catch {
        return
      }
      guard let self, !Task.isCancelled, self.state == .pendingClose else { return }
      self.pendingCloseTask = nil
      // Tracking can miss the popover arrow or deliver an exit before entry.
      // Keep checking while the pointer is in either actual window region.
      if self.pointerPresence().isInside {
        self.schedulePendingClose()
      } else {
        self.reset()
        self.close()
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
