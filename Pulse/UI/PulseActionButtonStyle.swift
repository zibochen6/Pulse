import SwiftUI

/// Compact actions with a visible boundary; feedback never resizes the page.
struct PulseActionButtonStyle: ButtonStyle {
  enum Emphasis { case primary, secondary }
  var emphasis: Emphasis = .secondary

  func makeBody(configuration: Configuration) -> some View {
    ActionBody(configuration: configuration, emphasis: emphasis)
  }

  private struct ActionBody: View {
    let configuration: ButtonStyleConfiguration
    let emphasis: Emphasis
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var focused: Bool

    private var isDestructive: Bool { configuration.role == .destructive }
    private var tint: Color { isDestructive ? .red : .accentColor }
    private var isPrimary: Bool { emphasis == .primary && !isDestructive }

    var body: some View {
      configuration.label
        .font(.system(size: PulseDesignTokens.caption, weight: .medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .foregroundStyle(isPrimary ? Color.white : (isDestructive ? Color.red : Color.primary))
        .background(background, in: RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall))
        .overlay {
          RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
            .strokeBorder(
              isPrimary
                ? tint.opacity(0.8)
                : (isDestructive ? tint.opacity(0.25) : Color(nsColor: .separatorColor)),
              lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall))
        .opacity(isEnabled ? 1 : 0.45)
        .pulseFocusAffordance(
          focused, shape: .roundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall))
        .focusable(true)
        .focused($focused)
        .pulseDisableSystemFocusRing()
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var background: Color {
      if isPrimary {
        return tint.opacity(configuration.isPressed ? 0.7 : (isHovered && isEnabled ? 0.9 : 1))
      }
      if configuration.isPressed { return tint.opacity(isDestructive ? 0.18 : 0.12) }
      if isHovered && isEnabled { return tint.opacity(0.08) }
      return isDestructive ? tint.opacity(0.05) : Color(nsColor: .controlBackgroundColor)
    }
  }
}
