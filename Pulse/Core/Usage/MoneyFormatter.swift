import Foundation

enum MoneyFormatter {
  /// Render the Decimal itself so a balance never rounds to a different amount.
  static func string(_ amount: Decimal, currency: String) -> String {
    let value = NSDecimalNumber(decimal: amount).stringValue
    switch currency {
    case "USD": return "$" + value
    case "CNY": return "¥" + value
    default: return "\(currency) \(value)"
    }
  }
}
