import AppKit

enum PopoverPointerRegion {
  case statusButton
  case content
}

/// Keeps pointer-exit timing separate from AppKit's immediate outside-click dismissal.
@MainActor
final class PopoverHoverController {
  private let delayNanoseconds: UInt64
  private let isPointerInside: @MainActor () -> Bool
  private let close: @MainActor () -> Void
  private var overStatusButton = false
  private var overContent = false
  private var pendingClose: Task<Void, Never>?

  init(
    delayNanoseconds: UInt64 = 400_000_000,
    isPointerInside: @escaping @MainActor () -> Bool,
    close: @escaping @MainActor () -> Void
  ) {
    self.delayNanoseconds = delayNanoseconds
    self.isPointerInside = isPointerInside
    self.close = close
  }

  func synchronize(statusButton: Bool, content: Bool) {
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
    pendingClose?.cancel()
    pendingClose = nil
    overStatusButton = false
    overContent = false
  }

  private func setInside(_ inside: Bool, region: PopoverPointerRegion) {
    switch region {
    case .statusButton:
      overStatusButton = inside
    case .content:
      overContent = inside
    }
    updateCloseSchedule()
  }

  private func updateCloseSchedule() {
    pendingClose?.cancel()
    pendingClose = nil
    guard !overStatusButton && !overContent else { return }

    let delayNanoseconds = self.delayNanoseconds
    pendingClose = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: delayNanoseconds)
      } catch {
        return
      }
      guard let self else { return }
      guard !Task.isCancelled, !overStatusButton, !overContent else { return }
      pendingClose = nil
      // An enter event can be missed while the pointer is inside the popover
      // window (including its arrow). Keep checking until it actually leaves.
      if isPointerInside() {
        updateCloseSchedule()
        return
      }
      close()
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

  @objc func mouseEntered(with event: NSEvent) {
    onEnter()
  }

  @objc func mouseExited(with event: NSEvent) {
    onExit()
  }
}
