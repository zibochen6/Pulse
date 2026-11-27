import SwiftUI

/// Anchor measurements are passive in production and let rendering tests inspect
/// the actual SwiftUI placements instead of duplicating layout arithmetic.
struct ProviderHeaderBoundsKey: PreferenceKey {
  static let defaultValue: [String: Anchor<CGRect>] = [:]

  static func reduce(
    value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}
