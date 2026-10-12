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
        .overlay {
          if focused {
            RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
              .inset(by: -1)
              .strokeBorder(Color.accentColor, lineWidth: 2)
              .allowsHitTesting(false)
          }
        }
        .focusable(true)
        .focused($focused)
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

/// Unified capsule "tab" used for dashboard column switching and local task
/// filters. Selection, hover and keyboard value all read consistently.
struct PulsePillTab: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovered = false
  @FocusState private var focused: Bool

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: PulseDesignTokens.label, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? .primary : .secondary)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(background, in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
    .overlay {
      if focused {
        Capsule()
          .inset(by: -1)
          .strokeBorder(Color.accentColor, lineWidth: 2)
          .allowsHitTesting(false)
      }
    }
    .focusable(true)
    .focused($focused)
    .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
  }

  private var background: Color {
    if isSelected { return PulseDesignTokens.selectedFill }
    return isHovered ? PulseDesignTokens.hoverFill : .clear
  }
}

/// Shared hover/press treatment for task rows, so local and dashboard rows
/// react identically. Replaces the two near-duplicate per-feature styles.
/// Hover and press use distinct fills; motion is gated on Reduce Motion and a
/// focus ring is drawn when keyboard-focused.
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
        .overlay {
          if focused {
            RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
              .inset(by: -1)
              .strokeBorder(Color.accentColor, lineWidth: 2)
              .allowsHitTesting(false)
          }
        }
        .focusable(true)
        .focused($focused)
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
    }

    private func fill(_ pressed: Bool) -> Color {
      if pressed { return PulseDesignTokens.pressedFill }
      if isHovered { return PulseDesignTokens.hoverFill }
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
