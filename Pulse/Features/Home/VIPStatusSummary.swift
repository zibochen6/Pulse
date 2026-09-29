import Foundation
import SwiftUI

struct VIPStatusSummary: View {
  let state: UsageRefreshState
  let onOpenUsage: () -> Void

  var body: some View {
    Button(action: onOpenUsage) {
      HStack(spacing: 5) {
        VIPProviderIcon(size: 16)
        Text(VIPUsageFormatter.title(for: state))
          .font(.subheadline.weight(.medium))
          .monospacedDigit()
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .padding(.horizontal, 8)
      .frame(height: 28)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help("Open 88VIP usage details")
    .accessibilityLabel("88VIP usage: \(VIPUsageFormatter.title(for: state)). Open details")
    .accessibilityIdentifier("openVIPUsageButton")
  }
}

enum VIPUsageFormatter {
  static func title(for state: UsageRefreshState) -> String {
    switch state {
    case .loading:
      return "…"
    case .unavailable:
      return "--"
    case .failure:
      return "!"
    case .success(let snapshot):
      if snapshot.metrics.contains(.unlimited) { return "∞" }
      guard let balance = snapshot.metrics.compactMap(balanceAmount).first else { return "--" }
      return money(balance.amount, currency: balance.currency)
    }
  }

  static func money(_ amount: Decimal, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    let value = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "--"
    return currency == "USD" ? "$\(value)" : "\(currency) \(value)"
  }

  private static func balanceAmount(_ metric: UsageMetric) -> (amount: Decimal, currency: String)? {
    guard case .balance(let amount, let currency) = metric else { return nil }
    return (amount, currency)
  }
}
