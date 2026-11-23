import AppKit
import SwiftUI

/// A glanceable readout of the same state used by the menu bar item.
struct AIStatusSummary: View {
  let state: UsageRefreshState
  let onOpenUsage: () -> Void

  var body: some View {
    ProviderStatusButton(
      title: title, providerName: "Codex",
      identifier: "openUsageButton", onOpenUsage: onOpenUsage
    ) { CodexProviderIcon(size: 16) }
  }
  private var title: String {
    guard case .success(let snapshot) = state else { return UsageMenuFormatter.title(for: state) }
    let values = snapshot.quotaWindows.map { $0.remainingPercent.map { "\($0)%" } ?? "--" }
    return values.isEmpty ? "--" : values.joined(separator: " · ")
  }

}

struct AntigravityStatusSummary: View {
  let state: UsageRefreshState
  let onOpenUsage: () -> Void

  var body: some View {
    ProviderStatusButton(
      title: Self.title(for: state), providerName: ProviderID.antigravity.name,
      identifier: "openAntigravityUsageButton", onOpenUsage: onOpenUsage
    ) { AntigravityProviderIcon(size: 16) }
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

struct AntigravityProviderIcon: View {
  let size: CGFloat

  private static let artwork = Bundle.main.url(
    forResource: "AntigravityColorIcon", withExtension: "png"
  ).flatMap { NSImage(contentsOf: $0) }

  var body: some View {
    Group {
      if let artwork = Self.artwork {
        Image(nsImage: artwork).resizable().scaledToFit()
      } else {
        Image(systemName: "sparkle").foregroundStyle(Color.accentColor)
      }
    }
    .padding(size * 0.12)
    .frame(width: size, height: size)
    .background(.white, in: RoundedRectangle(cornerRadius: size * 0.24))
    .accessibilityHidden(true)
  }
}
