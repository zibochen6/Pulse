import AppKit
import QuartzCore
import SwiftUI

/// Ends native editing before swapping pages, then fades in the live body.
struct PopoverContentTransition<Content: View>: NSViewRepresentable {
  let page: PopoverPage
  let content: Content
  @Environment(\.pulseReduceMotion) private var reduceMotion

  init(page: PopoverPage, @ViewBuilder content: () -> Content) {
    self.page = page
    self.content = content()
  }

  func makeNSView(context: Context) -> Container {
    Container(rootView: wrapped(context), page: page)
  }
  func updateNSView(_ view: Container, context: Context) {
    view.update(rootView: wrapped(context), page: page, reduceMotion: reduceMotion)
  }
  private func wrapped(_ context: Context) -> AnyView {
    AnyView(
      content
        .environment(\.locale, context.environment.locale)
        .environment(\.colorScheme, context.environment.colorScheme)
        .environment(\.pulseReduceMotionOverride, context.environment.pulseReduceMotion)
        .environment(\.pulsePopoverFocus, context.environment.pulsePopoverFocus)
        .tint(PulseDesignTokens.accent))
  }

  final class Container: NSView {
    private let host: NSHostingView<AnyView>
    private var page: PopoverPage
    private static var fadeKey: String { "pageOpacity" }

    init(rootView: AnyView, page: PopoverPage) {
      host = NSHostingView(rootView: rootView)
      self.page = page
      super.init(frame: .zero)
      wantsLayer = true
      host.wantsLayer = true
      addSubview(host)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
      super.layout()
      host.frame = bounds
    }

    func update(rootView: AnyView, page: PopoverPage, reduceMotion: Bool) {
      let pageChanged = self.page != page
      if pageChanged || reduceMotion {
        host.layer?.removeAnimation(forKey: Self.fadeKey)
      }
      if pageChanged {
        window?.endEditing(for: nil)
        self.page = page
      }
      host.rootView = rootView
      guard pageChanged, !reduceMotion, window?.isVisible == true, !bounds.isEmpty else { return }
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0.84
      fade.toValue = 1
      fade.duration = 0.14
      fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
      host.layer?.add(fade, forKey: Self.fadeKey)
    }
  }
}
