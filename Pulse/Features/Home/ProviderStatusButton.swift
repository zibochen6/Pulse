import SwiftUI

/// Shared compact control. Only an individually oversized readout scrolls;
/// normal amounts keep every digit and provider controls wrap as a unit.
///
/// The readout has two levels on purpose: the provider name is a quiet 10pt
/// caption and the number is the semibold monospaced line the eye lands on.
/// Stacking keeps a normal amount on one row of the strip (`Codex` alone is
/// wider than `¥42.68`), while a long balance only widens its own control.
/// 28pt is exactly the two stacked lines, so the strip never changes height
/// between a short and a long amount.
struct ProviderStatusButton<Icon: View>: View {
  let title: String
  let providerName: String
  let identifier: String
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
      .padding(.horizontal, 3)
      .frame(height: 28)
      .contentShape(RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall))
    }
    .buttonStyle(PulseProviderStatusStyle())
    .help("Open \(providerName) usage details")
    .accessibilityLabel("\(providerName) usage: \(title). Open details")
    .accessibilityIdentifier(identifier)
    .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) { [identifier: $0] }
  }

  private var label: some View {
    HStack(spacing: 4) {
      icon()
      VStack(alignment: .leading, spacing: 1) {
        Text(providerName)
          .font(.system(size: 10, weight: .medium))
          .lineLimit(1)
          .foregroundStyle(.secondary)
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .monospacedDigit()
          .lineLimit(1)
          .foregroundStyle(.primary)
      }
    }
    .fixedSize(horizontal: true, vertical: false)
  }
}
