import SwiftUI

struct DeepSeekStatusSummary: View {
  let state: UsageRefreshState
  let onOpenUsage: () -> Void

  var body: some View {
    ProviderStatusButton(
      title: DeepSeekUsageFormatter.title(for: state), providerName: "DeepSeek",
      identifier: "openDeepSeekUsageButton", onOpenUsage: onOpenUsage
    ) { DeepSeekProviderIcon(size: 14) }
  }
}

enum DeepSeekUsageFormatter {
  static func title(for state: UsageRefreshState) -> String {
    switch state {
    case .loading: return "…"
    case .unavailable, .failure: return "!"
    case .success(let snapshot):
      let balances = snapshot.balances
      guard !snapshot.hasPartialDataFailure,
        let balance = balances.first(where: { $0.currency == "CNY" })
          ?? balances.first(where: { $0.currency == "USD" })
      else { return "!" }
      return MoneyFormatter.string(balance.amount, currency: balance.currency)
    }
  }
}
