import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  static let contentSize = NSSize(width: 720, height: 560)
  private(set) var isOpen = false
  var onOpenChanged: ((Bool) -> Void)?
  private let focus = PulsePopoverFocus()
  private var inputMonitor: Any?
  private var appearanceSubscription: AnyCancellable?

  init<Content: View>(config: AppConfig? = nil, rootView: Content) {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: Self.contentSize),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = PulseLocalization.string("Pulse Settings")
    window.isReleasedWhenClosed = false
    super.init(window: window)
    let content = rootView.frame(width: Self.contentSize.width, height: Self.contentSize.height)
      .environment(\.pulsePopoverFocus, focus)
    window.contentViewController = NSHostingController(
      rootView:
        content
        .environment(\.pulseHasNativeBackdrop, config != nil)
        .background {
          if let config { SettingsWindowBackdrop(config: config) }
        })
    window.setContentSize(Self.contentSize)
    window.center()
    window.delegate = self

    if let config {
      let originalBackground = window.backgroundColor
      let wasOpaque = window.isOpaque
      appearanceSubscription = config.$windowTransparencyPercent
        .combineLatest(config.$systemReducesTransparency)
        .map { percent, reducesTransparency in percent > 0 && !reducesTransparency }
        .removeDuplicates()
        .sink { [weak window] usesGlass in
          window?.backgroundColor = usesGlass ? .clear : originalBackground
          window?.isOpaque = usesGlass ? false : wasOpaque
        }
    }
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

private struct SettingsWindowBackdrop: View {
  @ObservedObject var config: AppConfig

  var body: some View {
    SettingsVisualEffect(isVisible: config.effectiveWindowTransparencyPercent > 0)
      .equatable()
      .accessibilityHidden(true)
      .allowsHitTesting(false)
  }
}

private struct SettingsVisualEffect: NSViewRepresentable, Equatable {
  let isVisible: Bool

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .sidebar
    view.blendingMode = .behindWindow
    view.state = .followsWindowActiveState
    view.isHidden = !isVisible
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    if view.isHidden == isVisible { view.isHidden = !isVisible }
  }
}
