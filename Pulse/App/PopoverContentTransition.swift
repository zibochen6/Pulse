import AppKit
import QuartzCore
import SwiftUI

/// Changes only the panel body. The outgoing view is a bitmap, never a live
/// NSTextField that can send a late callback into a saved or different draft.
struct PopoverContentTransition<Content: View>: NSViewRepresentable {
  let page: PopoverPage
  let content: Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .tint(PulseDesignTokens.accent))
  }

  final class Container: NSView {
    private let host: NSHostingView<AnyView>
    private var page: PopoverPage
    private var outgoing: NSImageView?
    private var revision = 0

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
      outgoing?.frame = bounds
    }

    func update(rootView: AnyView, page: PopoverPage, reduceMotion: Bool) {
      guard self.page != page else {
        host.rootView = rootView
        return
      }
      revision += 1
      let currentRevision = revision
      outgoing?.removeFromSuperview()
      outgoing = nil
      host.layer?.removeAllAnimations()
      host.alphaValue = 1
      window?.endEditing(for: nil)
      host.layoutSubtreeIfNeeded()
      if window != nil, !bounds.isEmpty,
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)
      {
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(bitmap)
        let snapshot = NoninteractiveSnapshot(frame: bounds)
        snapshot.image = image
        snapshot.imageScaling = .scaleAxesIndependently
        snapshot.setAccessibilityElement(false)
        addSubview(snapshot, positioned: .above, relativeTo: host)
        outgoing = snapshot
      }
      self.page = page
      host.rootView = rootView
      host.layoutSubtreeIfNeeded()
      guard let snapshot = outgoing else { return }
      host.alphaValue = 0
      if !reduceMotion {
        let movement = CABasicAnimation(keyPath: "transform.translation.x")
        movement.fromValue = page == .home ? -8 : 8
        movement.toValue = 0
        movement.duration = 0.2
        movement.timingFunction = CAMediaTimingFunction(name: .easeOut)
        host.layer?.add(movement, forKey: "pagePosition")
      }
      NSAnimationContext.runAnimationGroup { context in
        context.duration = reduceMotion ? 0.1 : 0.2
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        host.animator().alphaValue = 1
        snapshot.animator().alphaValue = 0
      } completionHandler: { [weak self, weak snapshot] in
        MainActor.assumeIsolated {
          snapshot?.removeFromSuperview()
          guard let self, self.revision == currentRevision else { return }
          self.outgoing = nil
        }
      }
    }
  }
}

private final class NoninteractiveSnapshot: NSImageView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
