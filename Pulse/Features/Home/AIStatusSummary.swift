import SwiftUI

/// A glanceable readout of the same state used by the menu bar item.
struct AIStatusSummary: View {
  let state: UsageRefreshState
  let onOpenUsage: () -> Void

  var body: some View {
    ProviderStatusButton(
      title: UsageMenuFormatter.title(for: state), providerName: "Codex",
      identifier: "openUsageButton", onOpenUsage: onOpenUsage
    ) { CodexProviderIcon(size: 18) }
  }
}

struct AntigravityStatusSummary: View {
  let state: UsageRefreshState
  let onOpenUsage: () -> Void

  var body: some View {
    ProviderStatusButton(
      title: Self.title(for: state), providerName: ProviderID.antigravity.name,
      identifier: "openAntigravityUsageButton", onOpenUsage: onOpenUsage
    ) { GeminiProviderIcon(size: 18) }
  }

  static func title(for state: UsageRefreshState) -> String {
    switch state {
    case .loading:
      return "…"
    case .unavailable:
      return "--"
    case .failure:
      return "!"
    case .success(let snapshot):
      let window = snapshot.quotaWindows.first {
        $0.bucketID == AntigravityQuotaBucket.fiveHour.rawValue
      }
      return window?.remainingPercent.map { "\($0)%" } ?? "--"
    }
  }
}

struct GeminiProviderIcon: View {
  let size: CGFloat

  var body: some View {
    Image(systemName: "sparkle")
      .font(.system(size: size, weight: .semibold))
      .foregroundStyle(PulseDesignTokens.accent)
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}
