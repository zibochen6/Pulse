import SwiftUI

/// A one-line quota control with the provider name in its accessibility label and help.
struct ProviderStatusButton<Icon: View>: View {
  let title: String
  let providerName: String
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
        .contentShape(RoundedRectangle(cornerRadius: PulseDesignTokens.cornerLarge))
    }
    .buttonStyle(PulseProviderStatusStyle())
    .help(
      PulseLocalization.format(
        isConfigured ? "Open %@ usage details" : "Connect %@", providerName)
    )
    .accessibilityLabel(
      isConfigured
        ? PulseLocalization.format("%@ usage: %@. Open details", providerName, title)
        : PulseLocalization.format("Connect %@", providerName)
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
        .foregroundStyle(isConfigured ? Color.primary : PulseDesignTokens.accent)
    }
    .fixedSize(horizontal: true, vertical: false)
  }
}
