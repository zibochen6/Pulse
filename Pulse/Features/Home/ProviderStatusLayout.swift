import SwiftUI

/// Wraps complete indicators at their measured ideal widths, leading aligned.
struct ProviderStatusLayout: Layout {
  var spacing: CGFloat = 5

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
    let idealSizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let idealWidth =
      idealSizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, subviews.count - 1)) * spacing
    let width = max(0, proposal.width ?? idealWidth)
    var frames: [CGRect] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    for (index, ideal) in idealSizes.enumerated() {
      let itemWidth = min(width, ideal.width)
      let size = subviews[index].sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
      if x > 0 && x + itemWidth > width {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      frames.append(CGRect(x: x, y: y, width: itemWidth, height: size.height))
      x += itemWidth + spacing
      rowHeight = max(rowHeight, size.height)
    }
    return (CGSize(width: width, height: y + rowHeight), frames)
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
