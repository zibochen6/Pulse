import SwiftUI

/// A one-line quota control with the provider name in its accessibility label and help.
struct ProviderStatusButton<Icon: View>: View {
  let title: String
  let provider: ProviderID
  let identifier: String
  var isConfigured: Bool = true
  let onOpenUsage: () -> Void
  @ViewBuilder let icon: () -> Icon

  var body: some View {
    Button(action: onOpenUsage) {
      label
        .padding(.horizontal, 5)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: PulseDesignTokens.cornerMedium))
    }
    .buttonStyle(PulseProviderStatusStyle(paper: provider.dashboardPaper))
    .help(
      PulseLocalization.format(
        isConfigured ? "Open %@ usage details" : "Connect %@", provider.name)
    )
    .accessibilityLabel(
      isConfigured
        ? PulseLocalization.format("%@ usage: %@. Open details", provider.name, title)
        : PulseLocalization.format("Connect %@", provider.name)
    )
    .accessibilityIdentifier(identifier)
    .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) { [identifier: $0] }
  }

  private var label: some View {
    HStack(spacing: 4) {
      icon()
      Text(isConfigured ? title : "＋")
        .font(.system(size: 13, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(isConfigured ? PulseDesignTokens.ink : PulseDesignTokens.accent)
    }
    .fixedSize(horizontal: true, vertical: false)
  }
}

extension ProviderID {
  var dashboardPaper: Color {
    switch self {
    case .codex: PulseDesignTokens.taskPaper
    case .vip: PulseDesignTokens.rosePaper
    case .deepSeek: PulseDesignTokens.skyPaper
    case .antigravity: PulseDesignTokens.mintPaper
    }
  }
}
