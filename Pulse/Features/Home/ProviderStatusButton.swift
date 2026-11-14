import SwiftUI

/// Shared compact control. Only an individually oversized readout scrolls;
/// normal amounts keep every digit and provider controls wrap as a unit.
///
/// Readable provider labels and a separate numeric line establish hierarchy.
/// A long balance widens its whole card; only a card wider than the available
/// surface scrolls, preserving every currency symbol and decimal digit.
struct ProviderStatusButton<Icon: View>: View {
  let title: String
  let providerName: String
  let identifier: String
  var isConfigured: Bool = true
  let onOpenUsage: () -> Void
  @ViewBuilder let icon: () -> Icon

  var body: some View {
    Button(action: onOpenUsage) {
      ViewThatFits(in: .horizontal) {
        label.fixedSize(horizontal: true, vertical: false)
        ScrollView(.horizontal, showsIndicators: false) {
          label.fixedSize(horizontal: true, vertical: false)
        }
      }
      .padding(.horizontal, 10)
      .frame(height: 52)
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
    HStack(spacing: 6) {
      icon()
      VStack(alignment: .leading, spacing: 3) {
        Text(providerName)
          .font(.system(size: PulseDesignTokens.caption, weight: .medium))
          .lineLimit(1)
          .foregroundStyle(.secondary)
        Group {
          if isConfigured {
            Text(title).monospacedDigit()
          } else {
            Text("Connect")
          }
        }
        .font(.system(size: 15, weight: .semibold))
        .lineLimit(1)
        .foregroundStyle(isConfigured ? Color.primary : PulseDesignTokens.accent)
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }
}
