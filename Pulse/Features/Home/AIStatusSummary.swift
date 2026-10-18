import SwiftUI

/// A glanceable readout of the same state used by the menu bar item.
struct AIStatusSummary: View {
  let state: UsageRefreshState
  let onOpenUsage: () -> Void

  var body: some View {
    ProviderStatusButton(
      title: UsageMenuFormatter.title(for: state), providerName: "Codex",
      identifier: "openUsageButton", onOpenUsage: onOpenUsage
    ) { CodexProviderIcon(size: 14) }
  }
}
