import SwiftUI

/// Compact actions with a visible boundary; feedback never resizes the page.
struct PulseActionButtonStyle: ButtonStyle {
  enum Emphasis {
    case primary
    case secondary
    case toolbar(isActive: Bool = false)
  }
  var emphasis: Emphasis = .secondary

  func makeBody(configuration: Configuration) -> some View {
    ActionBody(configuration: configuration, emphasis: emphasis)
  }

  private struct ActionBody: View {
    let configuration: ButtonStyleConfiguration
    let emphasis: Emphasis
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @FocusState private var focused: Bool

    private var isPressed: Bool { isEnabled && configuration.isPressed }
    private var isDestructive: Bool { configuration.role == .destructive }
    private var tint: Color {
      isDestructive ? PulseDesignTokens.destructive : PulseDesignTokens.accent
    }
    private var isPrimary: Bool {
      if case .primary = emphasis { return !isDestructive }
      return false
    }
    private var toolbarIsActive: Bool? {
      if case .toolbar(let isActive) = emphasis { return isActive }
      return nil
    }
    private var border: Color {
      if isPrimary { return .clear }
      if let toolbarIsActive {
        return toolbarIsActive ? tint.opacity(0.22) : PulseDesignTokens.border
      }
      return isDestructive ? tint.opacity(0.25) : PulseDesignTokens.border.opacity(0.7)
    }

    var body: some View {
      label
        .foregroundStyle(
          isPrimary ? PulseDesignTokens.actionInk : (isDestructive ? tint : PulseDesignTokens.ink)
        )
        .background {
          RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
            .fill(background)
            .pulsePointerFeedback(isPressed: isPressed, isHovered: isHovered)
        }
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
    }

    @ViewBuilder
    private var label: some View {
      if toolbarIsActive != nil {
        configuration.label
          .font(.system(size: PulseDesignTokens.caption, weight: .medium))
          .lineLimit(1)
          .padding(.horizontal, 6)
          .frame(maxWidth: .infinity)
          .frame(height: 32)
      } else {
        configuration.label
          .font(.system(size: PulseDesignTokens.footnote, weight: .medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .frame(minHeight: 32)
      }
    }

    private var background: Color {
      if let toolbarIsActive {
        if isPressed { return PulseDesignTokens.pressedFill }
        if isHovered && isEnabled { return tint.opacity(toolbarIsActive ? 0.18 : 0.10) }
        return toolbarIsActive ? PulseDesignTokens.selectedFill : PulseDesignTokens.secondarySurface
      }
      if isPrimary {
        if isPressed { return PulseDesignTokens.primaryActionPressed }
        return isHovered && isEnabled
          ? PulseDesignTokens.primaryActionHover : PulseDesignTokens.primaryActionFill
      }
      if isPressed { return tint.opacity(isDestructive ? 0.18 : 0.12) }
      if isHovered && isEnabled { return tint.opacity(0.08) }
      return isDestructive ? tint.opacity(0.05) : PulseDesignTokens.surface
    }
  }
}
