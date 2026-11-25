import Foundation

/// Independent reasons to keep the transient surface alive. Ending a menu
/// must not release an editor or a drag that is still in progress. This model
/// owns no timers or pointer geometry; the existing hover controller does.
@MainActor
final class PopoverInteractionHolds {
  enum Source: Hashable {
    case keyboardNavigation
    case taskEditor
    case quickCopyEditor
    case tagEditor
    case menu(ObjectIdentifier)
    case drag(UUID)
    case tagChooser
  }

  struct Lease: Equatable {
    fileprivate let source: Source
    fileprivate let id: UUID
  }

  var onChange: ((Bool) -> Void)?
  var isActive: Bool { !leases.isEmpty }
  private var leases: [Source: UUID] = [:]

  /// Idempotent state updates are useful for an aggregate editor callback.
  func set(_ source: Source, active: Bool) {
    let wasActive = isActive
    if active {
      if leases[source] == nil { leases[source] = UUID() }
    } else {
      leases.removeValue(forKey: source)
    }
    notifyIfChanged(wasActive)
  }

  /// A native lifecycle can keep the returned lease. An old callback cannot
  /// release a newer session, including after reset and rapid reopening.
  @discardableResult
  func begin(_ source: Source) -> Lease {
    let wasActive = isActive
    let lease = Lease(source: source, id: UUID())
    leases[source] = lease.id
    notifyIfChanged(wasActive)
    return lease
  }

  func end(_ lease: Lease) {
    guard leases[lease.source] == lease.id else { return }
    let wasActive = isActive
    leases.removeValue(forKey: lease.source)
    notifyIfChanged(wasActive)
  }

  func reset() {
    let wasActive = isActive
    leases.removeAll()
    notifyIfChanged(wasActive)
  }

  private func notifyIfChanged(_ wasActive: Bool) {
    if wasActive != isActive { onChange?(isActive) }
  }
}
