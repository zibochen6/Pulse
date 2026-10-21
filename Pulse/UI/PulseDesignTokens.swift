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
  /// The popover's own name in the toolbar. Small on purpose: the panel is a
  /// utility surface, not a window title bar.
  static let toolbarTitle: CGFloat = 15

  // Corner radii.
  static let cornerSmall: CGFloat = 6
  static let cornerMedium: CGFloat = 8
  static let cornerLarge: CGFloat = 12

  // Rhythm.
  static let gap: CGFloat = 8
  /// Leading/trailing inset shared by the toolbar, the usage strip and the
  /// task list, so all three columns line up on one edge.
  static let contentInset: CGFloat = 14
  /// Brand mark: a small rounded tile that never competes with the task list.
  static let brandMarkSize: CGFloat = 22
  /// Height of a task row's text band (single line at `taskBody` plus padding).
  static let taskRowHeight: CGFloat = 36

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
  // Durations follow the interaction contract: pointer feedback 80–140 ms,
  // tab/page changes 160–200 ms, the composer 180–220 ms, completion ~200 ms.
  // None of them may block input, so every call site animates a value change
  // rather than a gesture.
  //
  // Every call site gates these on Reduce Motion; the tokens themselves stay
  // unconditional so there is exactly one place to tune the feel.
  static var hoverAnimation: Animation { .snappy(duration: 0.12, extraBounce: 0) }
  static var pressAnimation: Animation { .snappy(duration: 0.09, extraBounce: 0) }
  /// A discrete choice the user just made: a check, a tab becoming selected.
  static var selectionAnimation: Animation { .snappy(duration: 0.20, extraBounce: 0.06) }
  /// The selected pill's plate sliding between tags. 160–200 ms with almost no
  /// overshoot: the plate is a spatial hint, not a bounce.
  static var tabSwitchAnimation: Animation { .snappy(duration: 0.18, extraBounce: 0.04) }
  /// The inline composer growing out of its entry point.
  static var composerAnimation: Animation { .snappy(duration: 0.20, extraBounce: 0) }
  /// Home ⇄ Usage ⇄ Settings. Short on purpose: a menu-bar popover should feel
  /// like one surface changing, not like a screen sliding over another.
  static var pageTransitionAnimation: Animation { .snappy(duration: 0.18, extraBounce: 0) }
  /// Tap → save → check, all as one continuous acknowledgement. A finished
  /// task stays exactly where it is and only strikes through, so nothing in
  /// this curve is spent on moving a row anywhere.
  static var completionAnimation: Animation { .snappy(duration: 0.20, extraBounce: 0.04) }
  /// Reordering is spatial, so it may overshoot slightly as pills make room.
  static var reorderAnimation: Animation { .snappy(duration: 0.26, extraBounce: 0.12) }
  static var insertionAnimation: Animation { .snappy(duration: 0.18, extraBounce: 0) }
}
