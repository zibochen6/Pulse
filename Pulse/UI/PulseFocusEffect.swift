import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Settings focus compatibility

/// Compatibility for isolated views without a window focus policy.
struct PulseFocusRingSuppressor: NSViewRepresentable {
  func makeNSView(context: Context) -> FocusRingProbeView {
    let view = FocusRingProbeView(frame: .zero)
    view.isHidden = true
    return view
  }

  func updateNSView(_ nsView: FocusRingProbeView, context: Context) {
    nsView.suppressEnclosingFocusRing()
  }

  final class FocusRingProbeView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      suppressEnclosingFocusRing()
    }

    func suppressEnclosingFocusRing() {
      applyFocusRingSuppression()
      // SwiftUI can attach the control after the first layout pass.
      if !hasSearchedEnclosingButton {
        hasSearchedEnclosingButton = true
        DispatchQueue.main.async { [weak self] in
          self?.applyFocusRingSuppression()
        }
      }
    }

    private func applyFocusRingSuppression() {
      var ancestor: NSView? = superview
      while let current = ancestor {
        if let button = current as? NSButton {
          button.focusRingType = .none
          return
        }
        ancestor = current.superview
      }
    }

    private var hasSearchedEnclosingButton = false
  }
}

// MARK: - Focus affordance

/// Shape of the custom focus affordance. Pills use a capsule; everything else
/// uses a rounded rectangle matching the control's own radius.
enum PulseFocusShape {
  case capsule
  case roundedRectangle(cornerRadius: CGFloat)

  @ViewBuilder
  fileprivate func strokedView() -> some View {
    switch self {
    case .capsule:
      Capsule()
        .strokeBorder(PulseDesignTokens.focusStroke, lineWidth: 1)
    case .roundedRectangle(let cornerRadius):
      RoundedRectangle(cornerRadius: cornerRadius)
        .strokeBorder(PulseDesignTokens.focusStroke, lineWidth: 1)
    }
  }
}

@MainActor
final class PulsePopoverFocus: ObservableObject {
  @Published private(set) var showsKeyboardFocus = false

  func setKeyboardNavigation(_ active: Bool) {
    if showsKeyboardFocus != active { showsKeyboardFocus = active }
  }

  func beginPresentation(with event: NSEvent?) {
    setKeyboardNavigation(event?.type == .keyDown || event?.type == .keyUp)
  }

  func handleInput(_ event: NSEvent) {
    switch event.type {
    case .keyDown where event.keyCode == UInt16(kVK_Tab):
      setKeyboardNavigation(true)
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
      setKeyboardNavigation(false)
    default:
      break
    }
  }
}

private struct PulsePopoverFocusKey: EnvironmentKey {
  static let defaultValue: PulsePopoverFocus? = nil
}

extension EnvironmentValues {
  var pulsePopoverFocus: PulsePopoverFocus? {
    get { self[PulsePopoverFocusKey.self] }
    set { self[PulsePopoverFocusKey.self] = newValue }
  }
}

extension View {
  func pulseDisableSystemFocusRing() -> some View {
    modifier(PulseSystemFocusEffect())
  }

  func pulseFocusAffordance(_ isFocused: Bool, shape: PulseFocusShape) -> some View {
    overlay { PulseFocusOutline(isFocused: isFocused, shape: shape) }
  }
}

private struct PulseSystemFocusEffect: ViewModifier {
  @Environment(\.pulsePopoverFocus) private var popoverFocus

  func body(content: Content) -> some View {
    if popoverFocus == nil {
      content.background(PulseFocusRingSuppressor())
    } else if #available(macOS 14, *) {
      content.focusEffectDisabled()
    } else {
      content
    }
  }
}

private struct PulseFocusOutline: View {
  let isFocused: Bool
  let shape: PulseFocusShape
  @Environment(\.pulsePopoverFocus) private var popoverFocus

  var body: some View {
    if isFocused, let popoverFocus, #available(macOS 14, *) {
      KeyboardOutline(focus: popoverFocus, shape: shape)
    }
  }

  private struct KeyboardOutline: View {
    @ObservedObject var focus: PulsePopoverFocus
    let shape: PulseFocusShape

    var body: some View {
      if focus.showsKeyboardFocus {
        shape.strokedView()
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
  }
}
