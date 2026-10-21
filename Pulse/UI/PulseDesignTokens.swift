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

  // Selected pill (a slightly stronger neutral so selection reads).
  static let selectedFill: Color = Color(nsColor: .selectedControlColor).opacity(0.16)

  // Selected tab: an accent-tinted capsule so selection is the affordance
  // itself instead of a focus ring. Adaptive for Aqua / Dark Aqua and follows
  // the user's system accent.
  static let accentSelectionFill: Color = Color.accentColor.opacity(0.16)
  static let accentSelectionText: Color = Color(nsColor: .labelColor)

  // Keyboard focus affordance. Drawn ourselves (shape-matched) after the system
  // square ring is suppressed; see PulseFocusEffect.swift. Label color adapts
  // for Aqua / Dark Aqua and is legible over every hover/press fill above.
  static let focusStroke: Color = Color(nsColor: .labelColor).opacity(0.5)
  static let focusStrokeWidth: CGFloat = 1.5
  // Subtle rounded fill for focused rows (no outline, no box).
  static let focusFill: Color = Color.accentColor.opacity(0.08)

  // MARK: - Motion
  //
  // One curve per kind of feedback, so hover, press, selection, disclosure,
  // insertion and reorder all read as the same system instead of each surface
  // inventing its own duration. `extraBounce` is what separates "a control
  // acknowledged you" from "content moved somewhere", so spatial changes get
  // a little overshoot and discrete acknowledgements get none.
  //
  // Every call site gates these on Reduce Motion; the tokens themselves stay
  // unconditional so there is exactly one place to tune the feel.
  static var hoverAnimation: Animation { .snappy(duration: 0.14, extraBounce: 0) }
  static var pressAnimation: Animation { .snappy(duration: 0.10, extraBounce: 0) }
  /// A discrete choice the user just made: a check, a tab becoming selected.
  static var selectionAnimation: Animation { .snappy(duration: 0.20, extraBounce: 0.06) }
  /// Reordering is spatial, so it may overshoot slightly as pills make room.
  static var reorderAnimation: Animation { .snappy(duration: 0.26, extraBounce: 0.12) }
  static var disclosureAnimation: Animation { .snappy(duration: 0.22, extraBounce: 0.10) }
  static var insertionAnimation: Animation { .snappy(duration: 0.18, extraBounce: 0) }
}
