import AppKit
import SwiftUI

// MARK: - Square focus ring suppression

/// The system draws a square, non-rounded focus ring around rounded/capsule
/// controls (pills, icon buttons, rows), which clashes with the shapes used in
/// the popover. The reliable fix is to turn AppKit's ring off on the enclosing
/// `NSButton` and draw our own shape-matched affordance instead.
///
/// `.focusEffectDisabled()` only exists on macOS 14+, and the deployment target
/// is 13, so we walk the AppKit view hierarchy instead: SwiftUI backs
/// `.buttonStyle`/`Button` with an `NSButton`, so the enclosing control is a
/// short ancestor lookup. The lookup is retried on the next runloop turn
/// because SwiftUI may not have inserted the representable into the button's
/// hierarchy by the first `updateNSView`.
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
        .inset(by: -1)
        .strokeBorder(PulseDesignTokens.focusStroke, lineWidth: PulseDesignTokens.focusStrokeWidth)
    case .roundedRectangle(let cornerRadius):
      RoundedRectangle(cornerRadius: cornerRadius)
        .inset(by: -1)
        .strokeBorder(PulseDesignTokens.focusStroke, lineWidth: PulseDesignTokens.focusStrokeWidth)
    }
  }
}

extension View {
  /// Replaces the system square focus ring with no ring at all (the shared
  /// styles then draw their own shape-matched affordance).
  func pulseDisableSystemFocusRing() -> some View {
    background(PulseFocusRingSuppressor())
  }

  /// Draws the shared focus affordance: a 1.5pt stroke at ~0.5 opacity following
  /// the control's own shape. Never a rectangle around a capsule.
  func pulseFocusAffordance(_ isFocused: Bool, shape: PulseFocusShape) -> some View {
    overlay {
      if isFocused {
        shape
          .strokedView()
          .allowsHitTesting(false)
      }
    }
  }
}
