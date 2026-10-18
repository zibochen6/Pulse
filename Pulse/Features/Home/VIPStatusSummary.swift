import Foundation
import SwiftUI

struct VIPStatusSummary: View {
  let state: UsageRefreshState
  let onOpenUsage: () -> Void

  var body: some View {
    ProviderStatusButton(
      title: VIPUsageFormatter.title(for: state), providerName: "88VIP",
      identifier: "openVIPUsageButton", onOpenUsage: onOpenUsage
    ) { VIPProviderIcon(size: 14) }
  }
}

enum VIPUsageFormatter {
  static func title(for state: UsageRefreshState) -> String {
    switch state {
    case .loading:
      return "…"
    case .unavailable:
      return "!"
    case .failure:
      return "!"
    case .success(let snapshot):
      if snapshot.metrics.contains(.unlimited) { return "∞" }
      if snapshot.hasPartialDataFailure { return "!" }
      guard let balance = snapshot.metrics.compactMap(balanceAmount).first else { return "--" }
      return money(balance.amount, currency: balance.currency)
    }
  }

  static func money(_ amount: Decimal, currency: String) -> String {
    MoneyFormatter.string(amount, currency: currency)
  }

  private static func balanceAmount(_ metric: UsageMetric) -> (amount: Decimal, currency: String)? {
    guard case .balance(let amount, let currency) = metric else { return nil }
    return (amount, currency)
  }
}
