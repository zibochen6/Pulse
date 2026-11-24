import AppKit
import SwiftUI

/// Unified inline error banner. Replaces the ad-hoc red-text + borderless-button
/// blocks scattered across task and settings surfaces, so error copy and the
/// action verbs read the same everywhere.
struct PulseErrorBanner<Actions: View>: View {
  let message: String
  var accessibilityIdentifier: String? = nil
  @ViewBuilder let actions: Actions
  @Environment(\.pulseReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(message)
        .font(.system(size: PulseDesignTokens.caption))
        .foregroundStyle(PulseDesignTokens.destructive)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        actions
        Spacer(minLength: 0)
      }
      .font(.system(size: PulseDesignTokens.caption))
      .buttonStyle(.borderless)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      PulseDesignTokens.destructive.opacity(0.06),
      in: RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
    )
    .modifier(PulseAccessibilityIdentifier(identifier: accessibilityIdentifier))
    .transition(reduceMotion ? .opacity : .offset(y: -6).combined(with: .opacity))
  }
}

/// Icon-only tappable control (back, gear, refresh, provider add). Provides a
/// consistent hover/press fill and hit area so icon buttons feel the same as
/// text buttons. State lives in a nested View so `@State`/`@Environment` are
/// resolved correctly (same pattern as PulseActionButtonStyle.ActionBody).
struct PulseIconButtonStyle: ButtonStyle {
  var circular = false

  func makeBody(configuration: Configuration) -> some View {
    IconButtonBody(configuration: configuration, circular: circular)
  }

  private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let circular: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.pulseReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var focused: Bool

    private var radius: CGFloat { circular ? 14 : PulseDesignTokens.cornerSmall }

    var body: some View {
      configuration.label
        .frame(width: 28, height: 28)
        .contentShape(RoundedRectangle(cornerRadius: radius))
        .background(
          fill(configuration.isPressed, hovered: isHovered),
          in: RoundedRectangle(cornerRadius: radius)
        )
        .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
        .pulseFocusAffordance(focused, shape: .roundedRectangle(cornerRadius: radius))
        // Own the keyboard focus so hover/press fills can react to it, and
        // suppress AppKit's square ring in favour of the rounded affordance.
        .focusable(true)
        .focused($focused)
        .pulseDisableSystemFocusRing()
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
        .animation(
          reduceMotion ? nil : PulseDesignTokens.pressAnimation, value: configuration.isPressed)
    }

    private func fill(_ pressed: Bool, hovered: Bool) -> Color {
      if isEnabled && pressed { return PulseDesignTokens.pressedFill }
      if isEnabled && hovered {
        return circular ? PulseDesignTokens.pressedFill : PulseDesignTokens.hoverFill
      }
      return circular ? PulseDesignTokens.hoverFill : .clear
    }
  }
}

struct PulseSidebarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    SidebarButton(configuration: configuration)
  }

  private struct SidebarButton: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.pulseReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private let radius = PulseDesignTokens.cornerMedium

    var body: some View {
      configuration.label
        .padding(.vertical, 3)
        .background(
          configuration.isPressed
            ? PulseDesignTokens.pressedFill : (isHovered ? PulseDesignTokens.hoverFill : .clear),
          in: RoundedRectangle(cornerRadius: radius)
        )
        .contentShape(RoundedRectangle(cornerRadius: radius))
        .pulseFocusAffordance(isFocused, shape: .roundedRectangle(cornerRadius: radius))
        .focusable(true)
        .focused($isFocused)
        .pulseDisableSystemFocusRing()
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
    }
  }
}

/// Local tags use a static selection fill and a separate keyboard focus cue.
struct PulsePillTab: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: PulseDesignTokens.footnote, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? PulseDesignTokens.ink : PulseDesignTokens.muted)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: 140)
        .padding(.horizontal, 10)
        .frame(height: 28)
    }
    .buttonStyle(PulsePillTabStyle(isSelected: isSelected))
    .help(title)
    .accessibilityValue(PulseLocalization.string(isSelected ? "Selected" : "Not selected"))
  }
}

/// The pill's feedback lives in a ButtonStyle so it can read `isPressed`,
/// which a plain-styled Button never exposes to the view around it.
private struct PulsePillTabStyle: ButtonStyle {
  let isSelected: Bool

  func makeBody(configuration: Configuration) -> some View {
    PillBody(isSelected: isSelected, configuration: configuration)
  }

  private struct PillBody: View {
    let isSelected: Bool
    let configuration: ButtonStyleConfiguration
    @Environment(\.pulseReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var focused: Bool

    var body: some View {
      configuration.label
        .background(fill, in: Capsule())
        .contentShape(Capsule())
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
        .pulseFocusAffordance(focused, shape: .capsule)
        // Own the keyboard focus so the affordance can follow the capsule, and
        // suppress AppKit's square ring instead of drawing two of them.
        .focusable(true)
        .focused($focused)
        .pulseDisableSystemFocusRing()
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
        .animation(
          reduceMotion ? nil : PulseDesignTokens.pressAnimation, value: configuration.isPressed
        )
        .animation(reduceMotion ? nil : PulseDesignTokens.pressAnimation, value: focused)
    }

    private var fill: Color {
      if configuration.isPressed {
        return isSelected ? PulseDesignTokens.primaryActionPressed : PulseDesignTokens.pressedFill
      }
      if isSelected { return PulseDesignTokens.selectedFill }
      return isHovered ? PulseDesignTokens.hoverFill : .clear
    }
  }
}

/// Shared hover/press treatment for task rows. Replaces the two near-duplicate per-feature styles.
/// Hover and press use distinct fills; motion is gated on Reduce Motion.
/// Keyboard focus shows a subtle rounded fill (never a box outline), and the
/// system square ring is suppressed.
struct PulseRowButtonStyle: ButtonStyle {
  let isHovered: Bool

  func makeBody(configuration: Configuration) -> some View {
    RowBody(isHovered: isHovered, configuration: configuration)
  }

  private struct RowBody: View {
    let isHovered: Bool
    let configuration: ButtonStyleConfiguration
    @Environment(\.pulseReduceMotion) private var reduceMotion
    @Environment(\.pulsePopoverFocus) private var popoverFocus
    @FocusState private var focused: Bool

    var body: some View {
      configuration.label
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .background(
          fill(configuration.isPressed),
          in: RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
        )
        .opacity(configuration.isPressed ? 0.72 : 1)
        .pulseFocusAffordance(
          popoverFocus != nil && focused,
          shape: .roundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
        )
        .focusable(true)
        .focused($focused)
        .pulseDisableSystemFocusRing()
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: focused)
    }

    private func fill(_ pressed: Bool) -> Color {
      if pressed { return PulseDesignTokens.pressedFill }
      if isHovered { return PulseDesignTokens.hoverFill }
      if focused && popoverFocus == nil { return PulseDesignTokens.focusFill }
      return .clear
    }
  }
}

/// Hover/press/focus feedback for a compact quota readout in the Home usage
/// strip. The readout used to be `.plain`, i.e. the one tappable surface in the
/// popover with no acknowledgement at all; it now reacts exactly like the icon
/// buttons next to it (short, no bounce, shape-matched focus ring).
struct PulseProviderStatusStyle: ButtonStyle {
  let paper: Color

  func makeBody(configuration: Configuration) -> some View {
    StatusBody(configuration: configuration, paper: paper)
  }

  private struct StatusBody: View {
    let configuration: ButtonStyleConfiguration
    let paper: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.pulseReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var focused: Bool

    private let radius = PulseDesignTokens.cornerMedium

    var body: some View {
      configuration.label
        .overlay {
          RoundedRectangle(cornerRadius: radius)
            .fill(feedback)
            .allowsHitTesting(false)
        }
        .pulsePaper(paper, radius: radius)
        .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
        .pulseFocusAffordance(focused, shape: .roundedRectangle(cornerRadius: radius))
        .focusable(true)
        .focused($focused)
        .pulseDisableSystemFocusRing()
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
        .animation(
          reduceMotion ? nil : PulseDesignTokens.pressAnimation, value: configuration.isPressed
        )
        .animation(reduceMotion ? nil : PulseDesignTokens.pressAnimation, value: focused)
    }

    private var feedback: Color {
      guard isEnabled else { return .clear }
      if configuration.isPressed { return PulseDesignTokens.pressedFill }
      return isHovered ? PulseDesignTokens.hoverFill : .clear
    }
  }
}

/// Optional accessibility identifier applied only when provided.
private struct PulseAccessibilityIdentifier: ViewModifier {
  let identifier: String?
  func body(content: Content) -> some View {
    if let identifier {
      content.accessibilityIdentifier(identifier)
    } else {
      content
    }
  }
}

/// Inline prompt for a staged update. Deliberately calm: the update has already
/// been verified, so the only remaining action is a restart.
struct PulseUpdateBanner: View {
  let version: String
  let onRestart: () -> Void
  let onDismiss: () -> Void
  @Environment(\.pulseReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Pulse \(version) is ready", systemImage: "arrow.triangle.2.circlepath")
        .font(.system(size: PulseDesignTokens.caption, weight: .semibold))
        .foregroundStyle(PulseDesignTokens.accent)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        Button("Restart and update", action: onRestart)
          .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
          .accessibilityIdentifier("restartToUpdateButton")
        Button("Later", action: onDismiss)
          .buttonStyle(PulseActionButtonStyle())
          .accessibilityIdentifier("dismissUpdateBannerButton")
        Spacer(minLength: 0)
      }
    }
    .font(.system(size: PulseDesignTokens.caption))
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      PulseDesignTokens.accent.opacity(0.07),
      in: RoundedRectangle(cornerRadius: PulseDesignTokens.cornerLarge)
    )
    .padding(.horizontal, PulseDesignTokens.contentInset)
    .padding(.vertical, 6)
    .accessibilityIdentifier("updateReadyBanner")
    .transition(reduceMotion ? .opacity : .offset(y: -6).combined(with: .opacity))
  }
}
