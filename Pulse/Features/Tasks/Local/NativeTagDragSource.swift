import AppKit
import SwiftUI

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

  func makeNSView(context: Context) -> TagDragView {
    let view = TagDragView()
    view.update(self)
    return view
  }

  func updateNSView(_ view: TagDragView, context: Context) { view.update(self) }

  static func dismantleNSView(_ view: TagDragView, coordinator: ()) { view.finishSession() }

  final class TagDragView: NSView, NSDraggingSource {
    private var configuration: NativeTagDragSource?
    private var startEvent: NSEvent?
    private var sessionActive = false
    private var scrollTimer: Timer?
    private var scrollDirection: CGFloat = 0

    override var isFlipped: Bool { true }

    func update(_ configuration: NativeTagDragSource) {
      self.configuration = configuration
      toolTip = configuration.title
    }

    override func mouseDown(with event: NSEvent) {
      guard configuration?.isEnabled == true else { return }
      startEvent = event
    }

    override func mouseUp(with event: NSEvent) {
      defer { startEvent = nil }
      guard startEvent != nil, !sessionActive, configuration?.isEnabled == true,
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
      sessionActive = true
      configuration.onBegin()
      let session = beginDraggingSession(with: [item], event: event, source: self)
      session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(
      _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
      context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
      updateAutoscroll(at: screenPoint)
      reportLocation(at: screenPoint)
    }

    func draggingSession(
      _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
      finishSession()
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func finishSession() {
      scrollTimer?.invalidate()
      scrollTimer = nil
      scrollDirection = 0
      startEvent = nil
      guard sessionActive else { return }
      sessionActive = false
      configuration?.onEnd()
    }

    private func reportLocation(at screenPoint: NSPoint) {
      guard let window, sessionActive else { return }
      let local = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
      configuration?.onMove(local.x - bounds.midX)
    }

    private func updateAutoscroll(at point: NSPoint) {
      guard let scroll = enclosingScrollView, let window else { return }
      let clip = scroll.contentView
      let local = clip.convert(window.convertPoint(fromScreen: point), from: nil)
      let bounds = clip.bounds
      guard local.y >= bounds.minY - 16, local.y <= bounds.maxY + 16 else {
        setScrollDirection(0)
        return
      }
      let direction: CGFloat =
        local.x < bounds.minX + 24 ? -1 : (local.x > bounds.maxX - 24 ? 1 : 0)
      setScrollDirection(direction)
    }

    private func setScrollDirection(_ direction: CGFloat) {
      scrollDirection = direction
      guard direction != 0 else {
        scrollTimer?.invalidate()
        scrollTimer = nil
        return
      }
      guard scrollTimer == nil else { return }
      let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.scrollOneStep() }
      }
      scrollTimer = timer
      RunLoop.main.add(timer, forMode: .common)
      RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func scrollOneStep() {
      guard sessionActive, let scroll = enclosingScrollView, let document = scroll.documentView
      else {
        setScrollDirection(0)
        return
      }
      let clip = scroll.contentView
      let maximum = max(0, document.bounds.width - clip.bounds.width)
      let x = min(maximum, max(0, clip.bounds.minX + 10 * scrollDirection))
      clip.scroll(to: NSPoint(x: x, y: clip.bounds.minY))
      scroll.reflectScrolledClipView(clip)
      reportLocation(at: NSEvent.mouseLocation)
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
      let image = NSImage(size: bounds.size)
      image.lockFocus()
      NSColor.controlBackgroundColor.setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor.labelColor,
      ]
      (title as NSString).draw(
        in: bounds.insetBy(dx: 10, dy: 5), withAttributes: attributes)
      image.unlockFocus()
      return image
    }
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
