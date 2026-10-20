import AppKit
import SwiftUI

/// Unified inline error banner. Replaces the ad-hoc red-text + borderless-button
/// blocks scattered across task and settings surfaces, so error copy and the
/// action verbs read the same everywhere.
struct PulseErrorBanner<Actions: View>: View {
  let message: String
  var accessibilityIdentifier: String? = nil
  @ViewBuilder let actions: Actions

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(message)
        .font(.system(size: PulseDesignTokens.caption))
        .foregroundStyle(.red)
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
    .background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall))
    .modifier(PulseAccessibilityIdentifier(identifier: accessibilityIdentifier))
  }
}

/// Icon-only tappable control (back, gear, refresh, provider add). Provides a
/// consistent hover/press fill and hit area so icon buttons feel the same as
/// text buttons. State lives in a nested View so `@State`/`@Environment` are
/// resolved correctly (same pattern as PulseActionButtonStyle.ActionBody).
struct PulseIconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    IconButtonBody(configuration: configuration)
  }

  private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var focused: Bool

    var body: some View {
      configuration.label
        .frame(width: 28, height: 28)
        .contentShape(RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall))
        .background(
          fill(configuration.isPressed, hovered: isHovered),
          in: RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
        )
        .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
        .pulseFocusAffordance(
          focused, shape: .roundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall))
        // Own the keyboard focus so hover/press fills can react to it, and
        // suppress AppKit's square ring in favour of the rounded affordance.
        .focusable(true)
        .focused($focused)
        .pulseDisableSystemFocusRing()
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
        .animation(reduceMotion ? nil : PulseDesignTokens.pressAnimation, value: configuration.isPressed)
    }

    private func fill(_ pressed: Bool, hovered: Bool) -> Color {
      guard isEnabled else { return .clear }
      if pressed { return PulseDesignTokens.pressedFill }
      if hovered { return PulseDesignTokens.hoverFill }
      return .clear
    }
  }
}

/// Unified capsule "tab" for the local task tag bar. Selection reads as a
/// filled capsule (never a focus ring), and the
/// keyboard focus affordance follows the capsule shape so it cannot look like a
/// square box around a rounded control.
struct PulsePillTab: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Text(title)
        // 13pt keeps the tab row aligned with the 18pt brand glyph and leaves
        // the list room without a second type size in the task surface.
        .font(.system(size: PulseDesignTokens.footnote, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(background, in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .pulseDisableSystemFocusRing()
    .onHover { isHovered = $0 }
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
    .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
  }

  /// Selected: a filled capsule, so selection is the affordance itself.
  /// Unselected: hover fill only. Focus is handled by the enclosing control.
  /// The fill is not animated: selection is a discrete state change, and a
  /// fade-in would also leave the tab blank in off-window renders.
  private var background: Color {
    if isSelected { return PulseDesignTokens.accentSelectionFill }
    return isHovered ? PulseDesignTokens.hoverFill : .clear
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .focusable(true)
        .focused($focused)
        .pulseDisableSystemFocusRing()
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: focused)
    }

    private func fill(_ pressed: Bool) -> Color {
      if pressed { return PulseDesignTokens.pressedFill }
      if isHovered { return PulseDesignTokens.hoverFill }
      if focused { return PulseDesignTokens.focusFill }
      return .clear
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

extension PulseDesignTokens {
  static var hoverAnimation: Animation { .easeOut(duration: 0.12) }
  static var pressAnimation: Animation { .easeOut(duration: 0.08) }
}

/// Inline prompt for a staged update. Deliberately calm: the update has already
/// been verified, so the only remaining action is a restart.
struct PulseUpdateBanner: View {
  let version: String
  let onRestart: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "arrow.triangle.2.circlepath")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.tint)
      Text("Pulse \(version) is ready")
        .font(.system(size: PulseDesignTokens.caption, weight: .medium))
        .lineLimit(1)
      Spacer(minLength: 4)
      Button("Restart", action: onRestart)
        .accessibilityIdentifier("restartToUpdateButton")
      Button("Later", action: onDismiss)
        .accessibilityIdentifier("dismissUpdateBannerButton")
    }
    .font(.system(size: PulseDesignTokens.caption))
    .buttonStyle(.borderless)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      Color.accentColor.opacity(0.08),
      in: RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
    )
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .accessibilityIdentifier("updateReadyBanner")
  }
}
