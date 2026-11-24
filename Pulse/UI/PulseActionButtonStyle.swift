import SwiftUI

/// Compact actions with a visible boundary; feedback never resizes the page.
struct PulseActionButtonStyle: ButtonStyle {
  enum Emphasis {
    case primary
    case secondary
    case focusTimer(isRunning: Bool)
  }
  var emphasis: Emphasis = .secondary

  func makeBody(configuration: Configuration) -> some View {
    ActionBody(configuration: configuration, emphasis: emphasis)
  }

  private struct ActionBody: View {
    let configuration: ButtonStyleConfiguration
    let emphasis: Emphasis
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.pulseReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var focused: Bool

    private var isDestructive: Bool { configuration.role == .destructive }
    private var tint: Color {
      isDestructive ? PulseDesignTokens.destructive : PulseDesignTokens.accent
    }
    private var isPrimary: Bool {
      if case .primary = emphasis { return !isDestructive }
      return false
    }
    private var timerIsRunning: Bool? {
      if case .focusTimer(let isRunning) = emphasis { return isRunning }
      return nil
    }
    private var border: Color {
      if isPrimary || timerIsRunning != nil { return .clear }
      return isDestructive ? tint.opacity(0.25) : PulseDesignTokens.border.opacity(0.7)
    }

    var body: some View {
      configuration.label
        .font(.system(size: PulseDesignTokens.footnote, weight: .medium))
        .padding(.horizontal, timerIsRunning == nil ? 12 : 8)
        .padding(.vertical, 7)
        .frame(minHeight: 32)
        .foregroundStyle(
          isPrimary ? PulseDesignTokens.actionInk : (isDestructive ? tint : PulseDesignTokens.ink)
        )
        .background(background, in: RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall))
        .overlay {
          RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
            .strokeBorder(border, lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall))
        .opacity(isEnabled ? 1 : 0.45)
        .pulseFocusAffordance(
          focused, shape: .roundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
        )
        .focusable(true)
        .focused($focused)
        .pulseDisableSystemFocusRing()
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
        .animation(
          reduceMotion ? nil : PulseDesignTokens.pressAnimation, value: configuration.isPressed)
    }

    private var background: Color {
      if let timerIsRunning {
        if configuration.isPressed { return PulseDesignTokens.pressedFill }
        if isHovered && isEnabled { return tint.opacity(timerIsRunning ? 0.18 : 0.10) }
        return timerIsRunning ? PulseDesignTokens.selectedFill : PulseDesignTokens.secondarySurface
      }
      if isPrimary {
        if configuration.isPressed { return PulseDesignTokens.primaryActionPressed }
        return isHovered && isEnabled
          ? PulseDesignTokens.primaryActionHover : PulseDesignTokens.primaryActionFill
      }
      if configuration.isPressed { return tint.opacity(isDestructive ? 0.18 : 0.12) }
      if isHovered && isEnabled { return tint.opacity(0.08) }
      return isDestructive ? tint.opacity(0.05) : PulseDesignTokens.surface
    }
  }
}
