import AppKit
import SwiftUI

// MARK: - Settings focus compatibility

/// Retains the independent Settings window's existing AppKit ring handling.
/// When SwiftUI hosts the label inside an NSButton, disable that button's ring.
/// Popover controls use the scoped SwiftUI focus effect below.
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
  fileprivate func strokedView(inset: CGFloat, lineWidth: CGFloat) -> some View {
    switch self {
    case .capsule:
      Capsule()
        .inset(by: inset)
        .strokeBorder(PulseDesignTokens.focusStroke, lineWidth: lineWidth)
    case .roundedRectangle(let cornerRadius):
      RoundedRectangle(cornerRadius: cornerRadius)
        .inset(by: inset)
        .strokeBorder(PulseDesignTokens.focusStroke, lineWidth: lineWidth)
    }
  }
}

@MainActor
final class PulsePopoverFocus: ObservableObject {
  @Published private(set) var showsKeyboardFocus = false

  func setKeyboardNavigation(_ active: Bool) {
    if showsKeyboardFocus != active { showsKeyboardFocus = active }
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
    if isFocused {
      if let popoverFocus {
        if #available(macOS 14, *) {
          KeyboardOutline(focus: popoverFocus, shape: shape)
        }
      } else {
        shape.strokedView(inset: -1, lineWidth: PulseDesignTokens.focusStrokeWidth)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
  }

  private struct KeyboardOutline: View {
    @ObservedObject var focus: PulsePopoverFocus
    let shape: PulseFocusShape

    var body: some View {
      if focus.showsKeyboardFocus {
        shape.strokedView(inset: 0, lineWidth: 1)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
  }
}
