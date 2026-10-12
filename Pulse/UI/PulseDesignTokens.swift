import AppKit
import SwiftUI

/// Central design tokens so spacing, radii, type and feedback stay consistent
/// across the popover's three pages. Values intentionally map to the app's
/// existing 8px-ish rhythm; update them here rather than hard-coding per view.
enum PulseDesignTokens {
  // Type scale (pt). Used where a deliberate size is needed; body copy stays
  // at the system default so layout is not disturbed.
  static let label: CGFloat = 14
  static let footnote: CGFloat = 13
  static let caption: CGFloat = 12

  // Corner radii.
  static let cornerSmall: CGFloat = 6
  static let cornerMedium: CGFloat = 8
  static let cornerLarge: CGFloat = 12

  // Rhythm.
  static let gap: CGFloat = 8

  // Unified, neutral hover/press feedback so every tappable surface reacts the
  // same way instead of three unrelated tints.
  static let hoverFill: Color = Color(nsColor: .quaternaryLabelColor).opacity(0.16)
  static let pressedFill: Color = Color(nsColor: .quaternaryLabelColor).opacity(0.28)

  // Selected pill (kept as a slightly stronger neutral so selection reads).
  static let selectedFill: Color = Color(nsColor: .selectedControlColor).opacity(0.16)
}
