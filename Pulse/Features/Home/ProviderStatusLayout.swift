import SwiftUI

/// Distributes available width in one row while preserving intrinsic readout widths.
struct ProviderStatusLayout: Layout {
  var spacing: CGFloat = PulseDesignTokens.gap

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    arrangement(proposal: proposal, subviews: subviews).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let result = arrangement(
      proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
    for (index, frame) in result.frames.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading, proposal: ProposedViewSize(frame.size))
    }
  }

  private func arrangement(proposal: ProposedViewSize, subviews: Subviews) -> (
    size: CGSize, frames: [CGRect]
  ) {
    guard !subviews.isEmpty else { return (.zero, []) }
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let gaps = CGFloat(sizes.count - 1) * spacing
    let minimum = sizes.reduce(gaps) { $0 + $1.width }
    let width = max(minimum, proposal.width ?? minimum)
    let count = CGFloat(sizes.count)
    let equal = (width - gaps) / count
    let equalFits = sizes.allSatisfy { $0.width <= equal }
    var x: CGFloat = 0
    let frames = sizes.map { size in
      let itemWidth = equalFits ? equal : size.width + (width - minimum) / count
      let frame = CGRect(x: x, y: 0, width: itemWidth, height: size.height)
      x += itemWidth + spacing
      return frame
    }
    return (CGSize(width: width, height: sizes.map(\.height).max() ?? 0), frames)
  }
}

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
