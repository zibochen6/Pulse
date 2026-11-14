import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  static let contentSize = NSSize(width: 720, height: 560)
  private(set) var isOpen = false
  var onOpenChanged: ((Bool) -> Void)?

  init<Content: View>(rootView: Content) {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: Self.contentSize),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = PulseLocalization.string("Pulse Settings")
    window.isReleasedWhenClosed = false
    window.contentViewController = NSHostingController(
      rootView: rootView.frame(width: Self.contentSize.width, height: Self.contentSize.height))
    window.setContentSize(Self.contentSize)
    window.center()
    super.init(window: window)
    window.delegate = self
  }

  required init?(coder: NSCoder) { nil }

  func prepareToOpen() {
    isOpen = true
    onOpenChanged?(true)
  }

  func open() {
    prepareToOpen()
    NSApp.activate(ignoringOtherApps: true)
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    window?.endEditing(for: nil)
    isOpen = false
    onOpenChanged?(false)
  }
}
