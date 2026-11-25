import AppKit
import SwiftUI

extension View {
  /// Apply to the fill alone so pointer motion never animates a button's label or focus ring.
  func pulsePointerFeedback(isPressed: Bool, isHovered: Bool) -> some View {
    modifier(PulsePointerFeedback(isPressed: isPressed, isHovered: isHovered))
  }

  func pulseContentFeedback<Value: Equatable>(_ value: Value) -> some View {
    modifier(PulseContentFeedback(value: value))
  }
}

private struct PulsePointerFeedback: ViewModifier {
  let isPressed: Bool
  let isHovered: Bool
  @Environment(\.pulseReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    let isImmediate = reduceMotion || isPressed
    content
      .animation(isImmediate ? nil : PulseDesignTokens.releaseAnimation, value: isPressed)
      .animation(isImmediate ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
  }
}

private struct PulseContentFeedback<Value: Equatable>: ViewModifier {
  let value: Value
  @Environment(\.pulseReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .contentTransition(reduceMotion ? .identity : .opacity)
      .animation(reduceMotion ? nil : PulseDesignTokens.feedbackAnimation, value: value)
  }
}

/// A single glyph slot for asynchronous actions. Fast operations keep the idle mark.
struct PulseBusyGlyph<Idle: View>: View {
  private struct Request: Equatable {
    let startedAt: ContinuousClock.Instant?
  }

  private let request: Request?
  private let idle: Idle
  @State private var displayedRequest: Request?
  @Environment(\.pulseReduceMotion) private var reduceMotion

  init(
    isBusy: Bool, startedAt: ContinuousClock.Instant? = nil, @ViewBuilder idle: () -> Idle
  ) {
    request = isBusy ? Request(startedAt: startedAt) : nil
    self.idle = idle()
  }

  private var showsBusyIndicator: Bool {
    guard let request else { return false }
    let deadline = request.startedAt?.advanced(by: PulseDesignTokens.busyFeedbackDelay)
    return displayedRequest == request || deadline.map { $0 <= .now } == true
  }

  var body: some View {
    let showsBusy = showsBusyIndicator
    ZStack {
      // Keep the idle glyph's identity, including a checkbox that can change
      // as the operation finishes. Only its visibility changes.
      idle.opacity(showsBusy ? 0 : 1).accessibilityHidden(showsBusy)
      if showsBusy {
        Group {
          if reduceMotion {
            Image(systemName: "clock")
          } else {
            ProgressView().controlSize(.mini)
          }
        }
        .transition(.identity)
      } else if let request {
        Color.clear.frame(width: 0, height: 0)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
          .task(id: request) {
            let deadline = (request.startedAt ?? .now)
              .advanced(by: PulseDesignTokens.busyFeedbackDelay)
            do {
              try await Task.sleep(until: deadline, clock: .continuous)
              try Task.checkCancellation()
              displayedRequest = request
            } catch {
              // Completion, a new request and removal cancel the pending reveal.
            }
          }
      }
    }
    .onChange(of: request) { _ in displayedRequest = nil }
  }
}

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
        .foregroundStyle(PulseDesignTokens.destructive)
        .fixedSize(horizontal: false, vertical: true)
        .pulseContentFeedback(message)
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
    @State private var isHovered = false
    @FocusState private var focused: Bool

    private var radius: CGFloat { circular ? 14 : PulseDesignTokens.cornerSmall }

    var body: some View {
      configuration.label
        .frame(width: 28, height: 28)
        .contentShape(RoundedRectangle(cornerRadius: radius))
        .background {
          RoundedRectangle(cornerRadius: radius)
            .fill(fill(configuration.isPressed, hovered: isHovered))
            .pulsePointerFeedback(isPressed: configuration.isPressed, isHovered: isHovered)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .pulseFocusAffordance(focused, shape: .roundedRectangle(cornerRadius: radius))
        // Own the keyboard focus so hover/press fills can react to it, and
        // suppress AppKit's square ring in favour of the rounded affordance.
        .focusable(true)
        .focused($focused)
        .pulseDisableSystemFocusRing()
        .onHover { isHovered = $0 }
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
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private let radius = PulseDesignTokens.cornerMedium

    var body: some View {
      configuration.label
        .padding(.vertical, 3)
        .background {
          RoundedRectangle(cornerRadius: radius)
            .fill(fill)
            .pulsePointerFeedback(isPressed: configuration.isPressed, isHovered: isHovered)
        }
        .contentShape(RoundedRectangle(cornerRadius: radius))
        .pulseFocusAffordance(isFocused, shape: .roundedRectangle(cornerRadius: radius))
        .focusable(true)
        .focused($isFocused)
        .pulseDisableSystemFocusRing()
        .onHover { isHovered = $0 }
    }

    private var fill: Color {
      guard isEnabled else { return .clear }
      if configuration.isPressed { return PulseDesignTokens.pressedFill }
      return isHovered ? PulseDesignTokens.hoverFill : .clear
    }
  }
}

/// Local tags use a static selection fill and a separate keyboard focus cue.
struct PulsePillTab: View {
  let title: String
  let isSelected: Bool
  var isPointerPressed = false
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
    .buttonStyle(PulsePillTabStyle(isSelected: isSelected, isPointerPressed: isPointerPressed))
    .help(title)
    .accessibilityValue(PulseLocalization.string(isSelected ? "Selected" : "Not selected"))
  }
}

/// The pill's feedback lives in a ButtonStyle so it can read `isPressed`,
/// which a plain-styled Button never exposes to the view around it.
private struct PulsePillTabStyle: ButtonStyle {
  let isSelected: Bool
  let isPointerPressed: Bool

  func makeBody(configuration: Configuration) -> some View {
    PillBody(
      isSelected: isSelected, isPointerPressed: isPointerPressed, configuration: configuration)
  }

  private struct PillBody: View {
    let isSelected: Bool
    let isPointerPressed: Bool
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @FocusState private var focused: Bool

    private var isPressed: Bool { isEnabled && (configuration.isPressed || isPointerPressed) }

    var body: some View {
      configuration.label
        .background {
          ZStack {
            Capsule().fill(isSelected ? PulseDesignTokens.selectedFill : .clear)
            Capsule().fill(feedback)
              .pulsePointerFeedback(isPressed: isPressed, isHovered: isHovered)
          }
        }
        .contentShape(Capsule())
        .pulseFocusAffordance(focused, shape: .capsule)
        // Own the keyboard focus so the affordance can follow the capsule, and
        // suppress AppKit's square ring instead of drawing two of them.
        .focusable(true)
        .focused($focused)
        .pulseDisableSystemFocusRing()
        .onHover { isHovered = $0 }
    }

    private var feedback: Color {
      guard isEnabled else { return .clear }
      if isPressed { return PulseDesignTokens.pressedFill }
      return isHovered ? PulseDesignTokens.hoverFill : .clear
    }
  }
}

/// Shared hover/press treatment for task rows. Replaces the two near-duplicate per-feature styles.
/// Hover and press use distinct fills; motion is gated on Reduce Motion.
/// Keyboard focus uses the window affordance, with a rounded fill for isolated views.
struct PulseRowButtonStyle: ButtonStyle {
  let isHovered: Bool

  func makeBody(configuration: Configuration) -> some View {
    RowBody(isHovered: isHovered, configuration: configuration)
  }

  private struct RowBody: View {
    let isHovered: Bool
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.pulsePopoverFocus) private var popoverFocus
    @FocusState private var focused: Bool

    var body: some View {
      configuration.label
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .background {
          RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
            .fill(fill(configuration.isPressed))
            .animation(nil, value: focused)
            .pulsePointerFeedback(isPressed: configuration.isPressed, isHovered: isHovered)
        }
        .pulseFocusAffordance(
          popoverFocus != nil && focused,
          shape: .roundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall)
        )
        .focusable(true)
        .focused($focused)
        .pulseDisableSystemFocusRing()
    }

    private func fill(_ pressed: Bool) -> Color {
      if isEnabled && pressed { return PulseDesignTokens.pressedFill }
      if isEnabled && isHovered { return PulseDesignTokens.hoverFill }
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
  var radius = PulseDesignTokens.cornerMedium

  func makeBody(configuration: Configuration) -> some View {
    StatusBody(configuration: configuration, paper: paper, radius: radius)
  }

  private struct StatusBody: View {
    let configuration: ButtonStyleConfiguration
    let paper: Color
    let radius: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @FocusState private var focused: Bool

    var body: some View {
      configuration.label
        .overlay {
          RoundedRectangle(cornerRadius: radius)
            .fill(feedback)
            .pulsePointerFeedback(isPressed: configuration.isPressed, isHovered: isHovered)
            .allowsHitTesting(false)
        }
        .pulsePaper(paper, radius: radius)
        .opacity(isEnabled ? 1 : 0.45)
        .pulseFocusAffordance(focused, shape: .roundedRectangle(cornerRadius: radius))
        .focusable(true)
        .focused($focused)
        .pulseDisableSystemFocusRing()
        .onHover { isHovered = $0 }
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
  }
}
