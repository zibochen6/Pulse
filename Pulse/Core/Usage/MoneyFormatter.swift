import Foundation

enum MoneyFormatter {
  static func string(_ amount: Decimal, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    let value = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "--"
    switch currency {
    case "USD": return "$\(value)"
    case "CNY": return "¥\(value)"
    default: return "\(currency) \(value)"
    }
  }
}

extension UsageSnapshot {
  var balances: [(amount: Decimal, currency: String)] {
    metrics.compactMap {
      guard case .balance(let amount, let currency) = $0 else { return nil }
      return (amount, currency)
    }
  }
}
