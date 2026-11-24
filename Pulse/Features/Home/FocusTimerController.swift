import Combine
import Foundation

@MainActor
final class FocusTimerController: ObservableObject {
  static let sessionDuration: Duration = .seconds(30 * 60)

  @Published private(set) var isRunning = false
  @Published private(set) var justCompleted = false

  private let duration: Duration
  private let now: @MainActor () -> ContinuousClock.Instant
  private let onCompletion: @MainActor () -> Void
  private var deadline: ContinuousClock.Instant?
  private var timerTask: Task<Void, Never>?

  init(
    duration: Duration = FocusTimerController.sessionDuration,
    now: @escaping @MainActor () -> ContinuousClock.Instant = { .now },
    onCompletion: @escaping @MainActor () -> Void = {}
  ) {
    self.duration = duration
    self.now = now
    self.onCompletion = onCompletion
  }

  func start() {
    guard deadline == nil else { return }
    timerTask?.cancel()
    if justCompleted { justCompleted = false }
    let deadline = now().advanced(by: duration)
    self.deadline = deadline
    timerTask = Task { [weak self] in
      do {
        try await Task.sleep(until: deadline, clock: .continuous)
        try Task.checkCancellation()
      } catch {
        return
      }
      self?.finishIfDue()
    }
    isRunning = true
  }

  func cancel() {
    guard deadline != nil else { return }
    timerTask?.cancel()
    timerTask = nil
    deadline = nil
    isRunning = false
  }

  var remainingSeconds: Int {
    guard let deadline else { return 0 }
    let remaining = now().duration(to: deadline)
    guard remaining > .zero else { return 0 }
    let parts = remaining.components
    return Int(parts.seconds) + (parts.attoseconds > 0 ? 1 : 0)
  }

  func finishIfDue() {
    guard let deadline, now() >= deadline else { return }
    cancel()
    justCompleted = true
    timerTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(1.4))
      guard !Task.isCancelled, let self else { return }
      self.timerTask = nil
      self.justCompleted = false
    }
    onCompletion()
  }
}
