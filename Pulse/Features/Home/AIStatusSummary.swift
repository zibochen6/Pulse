import SwiftUI

/// A glanceable readout of the same state used by the menu bar item.
struct AIStatusSummary: View {
  let state: UsageRefreshState
  let onOpenUsage: () -> Void

  var body: some View {
    Button(action: onOpenUsage) {
      HStack(spacing: 5) {
        codexIcon
        Text(UsageMenuFormatter.title(for: state))
          .font(.caption.weight(.medium))
          .monospacedDigit()
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
      .frame(height: 24)
      .contentShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .help("Open Codex usage details")
    .accessibilityLabel("Codex usage: \(UsageMenuFormatter.title(for: state)). Open details")
    .accessibilityIdentifier("openUsageButton")
  }

  private var codexIcon: some View { CodexProviderIcon(size: 16) }
}
