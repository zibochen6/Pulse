import SwiftUI

/// Shared compact control. Only an individually oversized readout scrolls;
/// normal amounts keep every digit and provider controls wrap as a unit.
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
      .frame(height: 22)
      .contentShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .help("Open \(providerName) usage details")
    .accessibilityLabel("\(providerName) usage: \(title). Open details")
    .accessibilityIdentifier(identifier)
    .anchorPreference(key: ProviderHeaderBoundsKey.self, value: .bounds) { [identifier: $0] }
  }

  private var label: some View {
    HStack(spacing: 4) {
      icon()
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .lineLimit(1)
    }
    .foregroundStyle(.secondary)
  }
}
