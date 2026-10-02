import AppKit
import Combine
import UniformTypeIdentifiers

enum DashboardFilePanelResult {
  case selected(URL)
  case cancelled
  case failed
}

@MainActor
protocol DashboardFilePanelPresenting: AnyObject {
  func present(completion: @escaping @MainActor (DashboardFilePanelResult) -> Void)
  func focus()
}

/// Separates the file chooser from transient popover dismissal and its animation.
@MainActor
final class DashboardFilePicker: ObservableObject {
  private enum Phase { case idle, waitingForClose, choosing, saving }

  @Published private(set) var isSelecting = false
  @Published private(set) var errorMessage: String?
  private var phase: Phase = .idle
  private let panel: any DashboardFilePanelPresenting
  // Returns true when didClose will complete the handoff.
  private let closePopover: @MainActor () -> Bool
  private let isPopoverVisible: (@MainActor () -> Bool)?
  private let closeWaitNanoseconds: UInt64
  private let closeCheckNanoseconds: UInt64
  private var closeWaitTask: Task<Void, Never>?
  private let onSelection: @MainActor (URL) async -> Void
  private let onFinish: @MainActor () -> Void

  init(
    panel: any DashboardFilePanelPresenting = DashboardOpenPanel(),
    closePopover: @escaping @MainActor () -> Bool,
    isPopoverVisible: (@MainActor () -> Bool)? = nil,
    closeWaitNanoseconds: UInt64 = 2_000_000_000,
    closeCheckNanoseconds: UInt64 = 50_000_000,
    onSelection: @escaping @MainActor (URL) async -> Void,
    onFinish: @escaping @MainActor () -> Void
  ) {
    self.panel = panel
    self.closePopover = closePopover
    self.isPopoverVisible = isPopoverVisible
    self.closeWaitNanoseconds = closeWaitNanoseconds
    self.closeCheckNanoseconds = closeCheckNanoseconds
    self.onSelection = onSelection
    self.onFinish = onFinish
  }

  func requestSelection() {
    guard phase == .idle else {
      if phase == .choosing { panel.focus() }
      return
    }
    errorMessage = nil
    isSelecting = true
    phase = .waitingForClose
    if !closePopover() {
      popoverDidClose()
    } else if phase == .waitingForClose {
      startCloseCheck()
    }
  }

  func popoverDidClose() {
    guard phase == .waitingForClose else { return }
    closeWaitTask?.cancel()
    closeWaitTask = nil
    phase = .choosing
    panel.present { [weak self] result in self?.handle(result) }
  }

  private func startCloseCheck() {
    guard let isPopoverVisible else { return }
    closeWaitTask = Task { [weak self, closeWaitNanoseconds, closeCheckNanoseconds] in
      let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(closeWaitNanoseconds)))
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: closeCheckNanoseconds)
        } catch {
          return
        }
        guard let self, self.phase == .waitingForClose else { return }
        // A lost close callback must not leave the chooser permanently busy.
        // Check both the actual popover and its animated window in production.
        if !isPopoverVisible() {
          self.popoverDidClose()
          return
        }
        if ContinuousClock.now >= deadline {
          self.errorMessage =
            "Pulse could not open the file chooser. Close the popover and try again."
          self.finish()
          return
        }
      }
    }
  }

  private func handle(_ result: DashboardFilePanelResult) {
    guard phase == .choosing else { return }
    // Leave Choosing synchronously so repeated callbacks cannot enqueue saves.
    phase = .saving
    switch result {
    case .selected(let url):
      Task { [weak self] in
        guard let self else { return }
        await self.onSelection(url)
        self.finish()
      }
    case .cancelled:
      finish()
    case .failed:
      errorMessage = "Pulse could not open the file chooser. Try selecting the Dashboard again."
      finish()
    }
  }

  private func finish() {
    closeWaitTask?.cancel()
    closeWaitTask = nil
    phase = .idle
    isSelecting = false
    onFinish()
  }
}

@MainActor
private final class DashboardOpenPanel: DashboardFilePanelPresenting {
  private var activePanel: NSOpenPanel?

  func present(completion: @escaping @MainActor (DashboardFilePanelResult) -> Void) {
    // Leave the didClose callback before AppKit starts the next presentation.
    Task { @MainActor [weak self] in
      await Task.yield()
      self?.presentPanel(completion: completion)
    }
  }

  private func presentPanel(completion: @escaping @MainActor (DashboardFilePanelResult) -> Void) {
    let panel = NSOpenPanel()
    panel.title = "Select Apex Dashboard"
    panel.message =
      "Choose the Apex Dashboard Markdown file. Pulse can add tasks and save checkbox completion to this file."
    panel.prompt = "Select Dashboard"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    if let markdown = UTType(filenameExtension: "md") {
      panel.allowedContentTypes = [markdown]
    }
    activePanel = panel
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { [weak self, panel] response in
      panel.orderOut(nil)
      self?.activePanel = nil
      switch response {
      case .OK:
        if let url = panel.url { completion(.selected(url)) } else { completion(.failed) }
      case .cancel:
        completion(.cancelled)
      default:
        completion(.failed)
      }
    }
    panel.makeKeyAndOrderFront(nil)
  }

  func focus() {
    NSApp.activate(ignoringOtherApps: true)
    activePanel?.makeKeyAndOrderFront(nil)
  }
}
