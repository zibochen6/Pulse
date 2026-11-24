import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  static let contentSize = NSSize(width: 720, height: 560)
  private(set) var isOpen = false
  var onOpenChanged: ((Bool) -> Void)?
  private let focus = PulsePopoverFocus()
  private var inputMonitor: Any?

  init<Content: View>(rootView: Content) {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: Self.contentSize),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = PulseLocalization.string("Pulse Settings")
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.contentViewController = NSHostingController(
      rootView: rootView.frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .environment(\.pulsePopoverFocus, focus))
    window.setContentSize(Self.contentSize)
    window.center()
    window.delegate = self
  }

  required init?(coder: NSCoder) { nil }

  func prepareToOpen() {
    isOpen = true
    onOpenChanged?(true)
  }

  func open() {
    prepareToOpen()
    focus.beginPresentation(with: NSApp.currentEvent)
    if inputMonitor == nil {
      inputMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
      ) { [weak self] event in
        MainActor.assumeIsolated {
          if let self, let window = self.window, event.window === window {
            self.focus.handleInput(event)
          }
        }
        return event
      }
    }
    NSApp.activate(ignoringOtherApps: true)
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    if let inputMonitor {
      NSEvent.removeMonitor(inputMonitor)
      self.inputMonitor = nil
    }
    focus.setKeyboardNavigation(false)
    window?.endEditing(for: nil)
    isOpen = false
    onOpenChanged?(false)
  }
}
