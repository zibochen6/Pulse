import AppKit
import QuartzCore
import SwiftUI

@MainActor
struct DraggableTagTab: View {
  let source: NativeTagDragSource
  let isSelected: Bool
  @State private var isPointerPressed = false

  var body: some View {
    PulsePillTab(
      title: source.title, isSelected: isSelected,
      isPointerPressed: isPointerPressed, action: source.onSelect
    )
    .overlay { dragSurface.accessibilityHidden(true) }
  }

  private var dragSurface: NativeTagDragSource {
    var surface = source
    surface.onPointerPressChanged = { isPointerPressed = $0 }
    return surface
  }
}

/// SwiftUI's onDrag has no reliable cancellation callback on macOS 13. This
/// transparent mouse surface owns the native session so leaving the popover or
/// pressing Escape always releases its interaction hold. Keyboard activation
/// and accessibility continue to use the SwiftUI button underneath it.
@MainActor
struct NativeTagDragSource: NSViewRepresentable {
  let tagID: UUID
  let title: String
  let isEnabled: Bool
  let canMoveLeft: Bool
  let canMoveRight: Bool
  let onSelect: () -> Void
  let onBegin: () -> Void
  let onMove: (CGFloat) -> Void
  let onEnd: () -> Void
  let onRename: () -> Void
  let onDelete: () -> Void
  let onMoveLeft: () -> Void
  let onMoveRight: () -> Void
  var onPointerPressChanged: (Bool) -> Void = { _ in }

  func makeNSView(context: Context) -> TagDragView {
    let view = TagDragView()
    view.update(self, reduceMotion: context.environment.pulseReduceMotion)
    return view
  }

  func updateNSView(_ view: TagDragView, context: Context) {
    view.update(self, reduceMotion: context.environment.pulseReduceMotion)
  }

  static func dismantleNSView(_ view: TagDragView, coordinator: ()) { view.finishSession() }

  final class TagDragView: NSView, NSDraggingSource {
    private var configuration: NativeTagDragSource?
    private var startEvent: NSEvent?
    private var sessionActive = false
    private var reduceMotion = false
    private var dragPoint: NSPoint?
    private var cancelScrollClock: (() -> Void)?
    private var lastScrollTime: CFTimeInterval = 0
    private var requestedScrollX: CGFloat?
    private var appliedScrollX: CGFloat?

    override var isFlipped: Bool { true }

    func update(_ configuration: NativeTagDragSource, reduceMotion: Bool) {
      self.configuration = configuration
      self.reduceMotion = reduceMotion
      toolTip = configuration.title
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil { finishSession() }
    }

    override func mouseDown(with event: NSEvent) {
      guard let configuration, configuration.isEnabled else { return }
      startEvent = event
      configuration.onPointerPressChanged(true)
    }

    override func mouseUp(with event: NSEvent) {
      guard startEvent != nil else { return }
      clearPointerPress()
      guard !sessionActive, configuration?.isEnabled == true,
        bounds.contains(convert(event.locationInWindow, from: nil))
      else { return }
      configuration?.onSelect()
    }

    override func mouseDragged(with event: NSEvent) {
      guard !sessionActive, let startEvent, let configuration, configuration.isEnabled else {
        return
      }
      let distance = hypot(
        event.locationInWindow.x - startEvent.locationInWindow.x,
        event.locationInWindow.y - startEvent.locationInWindow.y)
      guard distance >= 4 else { return }
      let pasteboard = NSPasteboardItem()
      pasteboard.setString(configuration.tagID.uuidString, forType: .string)
      let item = NSDraggingItem(pasteboardWriter: pasteboard)
      item.setDraggingFrame(bounds, contents: dragImage(title: configuration.title))
      clearPointerPress()
      sessionActive = true
      configuration.onBegin()
      let session = beginDraggingSession(with: [item], event: event, source: self)
      session.animatesToStartingPositionsOnCancelOrFail = !reduceMotion
    }

    func draggingSession(
      _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
      context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, movedTo _: NSPoint) {
      let point = session.draggingLocation
      dragPoint = point
      updateAutoscroll(at: point)
      reportLocation(at: point)
    }

    func draggingSession(
      _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
      finishSession()
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func finishSession() {
      stopAutoscroll()
      clearPointerPress()
      dragPoint = nil
      guard sessionActive else { return }
      sessionActive = false
      configuration?.onEnd()
    }

    private func clearPointerPress() {
      guard startEvent != nil else { return }
      startEvent = nil
      configuration?.onPointerPressChanged(false)
    }

    private func reportLocation(at screenPoint: NSPoint) {
      guard let window, sessionActive else { return }
      let local = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
      configuration?.onMove(local.x - bounds.midX)
    }

    private func updateAutoscroll(at point: NSPoint) {
      guard let window, scrollParameters(at: point) != nil else {
        stopAutoscroll()
        return
      }
      guard cancelScrollClock == nil else { return }
      lastScrollTime = CACurrentMediaTime()
      if #available(macOS 14, *) {
        // The source pill can scroll out of view. The window stays on the
        // actual display and continues ticking for the duration of the drag.
        let target = ScrollDisplayTarget(view: self)
        let link = window.displayLink(target: target, selector: #selector(ScrollDisplayTarget.tick))
        cancelScrollClock = { link.invalidate() }
        link.add(to: .main, forMode: .common)
        link.add(to: .main, forMode: .eventTracking)
      } else {
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
          MainActor.assumeIsolated { self?.scrollOneStep(at: CACurrentMediaTime()) }
        }
        cancelScrollClock = { timer.invalidate() }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
      }
    }

    private func stopAutoscroll() {
      cancelScrollClock?()
      cancelScrollClock = nil
      requestedScrollX = nil
      appliedScrollX = nil
    }

    private func scrollParameters(at point: NSPoint)
      -> (scroll: NSScrollView, maximum: CGFloat, velocity: CGFloat)?
    {
      guard sessionActive, let scroll = enclosingScrollView, let document = scroll.documentView,
        let window
      else { return nil }
      let clip = scroll.contentView
      let local = clip.convert(window.convertPoint(fromScreen: point), from: nil)
      let maximum = max(0, document.bounds.width - clip.bounds.width)
      let velocity = TagEdgeAutoscroll.velocity(at: local, in: clip.bounds)
      guard TagEdgeAutoscroll.canScroll(from: clip.bounds.minX, to: maximum, velocity: velocity)
      else { return nil }
      return (scroll, maximum, velocity)
    }

    private func scrollOneStep(at time: CFTimeInterval) {
      guard let point = dragPoint, let (scroll, maximum, velocity) = scrollParameters(at: point)
      else {
        stopAutoscroll()
        return
      }
      let clip = scroll.contentView
      let currentX = clip.bounds.minX
      // Preserve fractional motion when AppKit rounds the clip origin to a pixel.
      // Rebase it if the native clip moves independently of the drag clock.
      let origin = appliedScrollX == currentX ? requestedScrollX ?? currentX : currentX
      let x = TagEdgeAutoscroll.origin(
        from: origin, to: maximum, velocity: velocity, elapsed: time - lastScrollTime)
      lastScrollTime = time
      requestedScrollX = x
      clip.scroll(to: NSPoint(x: x, y: clip.bounds.minY))
      appliedScrollX = clip.bounds.minX
      if clip.bounds.minX != currentX {
        scroll.reflectScrolledClipView(clip)
        reportLocation(at: point)
      }
      if !TagEdgeAutoscroll.canScroll(from: x, to: maximum, velocity: velocity) {
        stopAutoscroll()
      }
    }

    @available(macOS 14, *)
    @MainActor
    private final class ScrollDisplayTarget: NSObject {
      private weak var view: TagDragView?

      init(view: TagDragView) { self.view = view }

      @objc func tick(_: CADisplayLink) {
        view?.scrollOneStep(at: CACurrentMediaTime())
      }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
      guard let configuration, configuration.isEnabled else { return nil }
      let menu = NSMenu()
      menu.addItem(TagActionItem("Rename…", action: configuration.onRename))
      menu.addItem(TagActionItem("Delete list…", action: configuration.onDelete))
      menu.addItem(.separator())
      let left = TagActionItem("Move Left", action: configuration.onMoveLeft)
      left.isEnabled = configuration.canMoveLeft
      left.keyEquivalent = "\u{F702}"
      left.keyEquivalentModifierMask = [.option, .command]
      menu.addItem(left)
      let right = TagActionItem("Move Right", action: configuration.onMoveRight)
      right.isEnabled = configuration.canMoveRight
      right.keyEquivalent = "\u{F703}"
      right.keyEquivalentModifierMask = [.option, .command]
      menu.addItem(right)
      menu.autoenablesItems = false
      return menu
    }

    private func dragImage(title: String) -> NSImage {
      let appearance = effectiveAppearance
      return NSImage(size: bounds.size, flipped: false) { rect in
        appearance.performAsCurrentDrawingAppearance {
          NSColor.controlBackgroundColor.setFill()
          NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            .fill()
          let paragraph = NSMutableParagraphStyle()
          paragraph.lineBreakMode = .byTruncatingTail
          (title as NSString).draw(
            in: rect.insetBy(dx: 10, dy: 5),
            withAttributes: [
              .font: NSFont.systemFont(ofSize: 13, weight: .medium),
              .foregroundColor: NSColor.labelColor,
              .paragraphStyle: paragraph,
            ])
        }
        return true
      }
    }
  }
}

enum TagEdgeAutoscroll {
  static func velocity(at point: CGPoint, in viewport: CGRect) -> CGFloat {
    guard !viewport.isEmpty, viewport.insetBy(dx: -16, dy: -16).contains(point) else { return 0 }
    let edgeWidth = min(24, viewport.width / 2)
    let left = point.x - viewport.minX
    let right = viewport.maxX - point.x
    let progress = min(1, max(0, 1 - min(left, right) / edgeWidth))
    return (left < right ? -360 : 360) * progress
  }

  static func canScroll(from origin: CGFloat, to maximum: CGFloat, velocity: CGFloat) -> Bool {
    (velocity < 0 && origin > 0) || (velocity > 0 && origin < maximum)
  }

  static func origin(
    from origin: CGFloat, to maximum: CGFloat, velocity: CGFloat, elapsed: TimeInterval
  ) -> CGFloat {
    let interval = min(1.0 / 20, max(0, elapsed))
    return min(maximum, max(0, origin + velocity * interval))
  }
}

@MainActor
private final class TagActionItem: NSMenuItem {
  private let handler: () -> Void

  init(_ title: String, action: @escaping () -> Void) {
    handler = action
    super.init(
      title: PulseLocalization.string(title), action: #selector(performAction), keyEquivalent: "")
    target = self
  }

  required init(coder: NSCoder) { fatalError("TagActionItem is created programmatically") }

  @objc private func performAction() { handler() }
}

struct TagScrollMetrics: Equatable {
  var width: CGFloat = 0
  var minX: CGFloat = 0
  var viewportWidth: CGFloat = 0

  struct Buttons: Equatable {
    let overflows: Bool
    let hasPrevious: Bool
    let hasNext: Bool

    init(metrics: TagScrollMetrics = TagScrollMetrics()) {
      overflows = metrics.width > metrics.viewportWidth + 1
      hasPrevious = metrics.minX < -1
      hasNext = metrics.width + metrics.minX > metrics.viewportWidth + 1
    }
  }
}

/// Read the actual native clip/document geometry. SwiftUI's ScrollView may
/// consume geometry preferences internally; using its clip view also gives
/// precise updates after trackpad scrolling and native drag autoscroll.
@MainActor
struct NativeTagScrollMetricsReader: NSViewRepresentable {
  var onChange: (TagScrollMetrics) -> Void

  func makeNSView(context: Context) -> MetricsView {
    let view = MetricsView()
    view.onChange = onChange
    return view
  }

  func updateNSView(_ view: MetricsView, context: Context) {
    view.onChange = onChange
    view.scheduleMeasurement()
  }

  static func dismantleNSView(_ view: MetricsView, coordinator: ()) { view.detach() }

  final class MetricsView: NSView {
    var onChange: (TagScrollMetrics) -> Void = { _ in }
    private var observers: [NSObjectProtocol] = []
    private weak var observedScroll: NSScrollView?
    private var lastMetrics: TagScrollMetrics?
    private var measurementScheduled = false

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil { detach() } else { scheduleMeasurement() }
    }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      scheduleMeasurement()
    }

    func scheduleMeasurement() {
      guard !measurementScheduled else { return }
      measurementScheduled = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.measurementScheduled = false
        guard self.window != nil else { return }
        self.measure()
      }
    }

    private func measure() {
      guard let scroll = enclosingScrollView else { return }
      if observedScroll !== scroll {
        detach()
        observedScroll = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.documentView?.postsFrameChangedNotifications = true
        for (name, object) in [
          (NSView.boundsDidChangeNotification, scroll.contentView as NSView),
          (NSView.frameDidChangeNotification, scroll.documentView ?? scroll),
        ] {
          observers.append(
            NotificationCenter.default.addObserver(
              forName: name, object: object, queue: .main
            ) { [weak self] _ in
              MainActor.assumeIsolated { self?.scheduleMeasurement() }
            })
        }
      }
      let metrics = TagScrollMetrics(
        width: scroll.documentView?.bounds.width ?? bounds.width,
        minX: -scroll.contentView.bounds.minX,
        viewportWidth: scroll.contentView.bounds.width)
      guard metrics != lastMetrics else { return }
      lastMetrics = metrics
      onChange(metrics)
    }

    func detach() {
      for observer in observers { NotificationCenter.default.removeObserver(observer) }
      observers.removeAll()
      observedScroll = nil
    }
  }
}
