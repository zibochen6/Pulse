import AppKit
import QuartzCore
import SwiftUI

/// Ends native editing and replaces the live body when the route changes.
struct PopoverContentTransition<Page: Equatable, Content: View>: NSViewRepresentable {
  let page: Page
  let content: Content
  @Environment(\.pulseReduceMotion) private var reduceMotion

  init(page: Page, @ViewBuilder content: () -> Content) {
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
        .environment(\.pulseHasNativeBackdrop, context.environment.pulseHasNativeBackdrop)
        .environment(\.pulsePaperOpacity, context.environment.pulsePaperOpacity)
        .tint(PulseDesignTokens.accent))
  }

  final class Container: NSView {
    private let host: NSHostingView<AnyView>
    private var page: Page
    private var pageGeneration: UInt64 = 0
    private static var fadeKey: String { "pageOpacity" }

    init(rootView: AnyView, page: Page) {
      host = NSHostingView(rootView: AnyView(rootView.id(UInt64(0))))
      self.page = page
      super.init(frame: .zero)
      wantsLayer = true
      host.wantsLayer = true
      host.frame = bounds
      host.autoresizingMask = [.width, .height]
      addSubview(host)
    }
    required init?(coder: NSCoder) { nil }

    func update(rootView: AnyView, page: Page, reduceMotion: Bool) {
      let pageChanged = self.page != page
      let layer = host.layer
      let interruptedOpacity: Float? =
        pageChanged && layer?.animation(forKey: Self.fadeKey) != nil
        ? layer?.presentation()?.opacity : nil

      if pageChanged {
        endEditingInOutgoingPage()
        self.page = page
        pageGeneration &+= 1
      }
      host.rootView = AnyView(rootView.id(pageGeneration))

      if pageChanged || reduceMotion {
        layer?.removeAnimation(forKey: Self.fadeKey)
      }
      guard pageChanged, !reduceMotion, window?.isVisible == true, !bounds.isEmpty else { return }

      let opacity = interruptedOpacity ?? 0.90
      guard opacity < 1 else { return }
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = opacity
      fade.toValue = 1
      fade.duration = PulseDesignTokens.contentFadeDuration
      fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
      layer?.add(fade, forKey: Self.fadeKey)
    }

    private func endEditingInOutgoingPage() {
      guard let window, let editor = window.firstResponder as? NSTextView else { return }
      let field = editor.isFieldEditor ? editor.delegate as? NSView : nil
      guard editor.isDescendant(of: host) || field?.isDescendant(of: host) == true else { return }

      // Let AppKit finish marked text and notify the old field before replacing it.
      if !window.makeFirstResponder(nil), editor.isFieldEditor, window.firstResponder === editor {
        window.endEditing(for: field)
      }
    }
  }
}
