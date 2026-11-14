import AppKit
import SwiftUI

/// Shared visual and motion vocabulary for the menu-bar surface and Settings.
/// Colors resolve against native appearance, keeping both surfaces opaque and
/// legible without relying on the wallpaper behind a popover.
enum PulseDesignTokens {
  static let label: CGFloat = 14
  static let footnote: CGFloat = 13
  static let caption: CGFloat = 12
  static let toolbarTitle: CGFloat = 16

  static let cornerSmall: CGFloat = 8
  static let cornerMedium: CGFloat = 10
  static let cornerLarge: CGFloat = 12
  static let gap: CGFloat = 8
  static let contentInset: CGFloat = 16
  static let brandMarkSize: CGFloat = 28
  static let taskRowHeight: CGFloat = 36

  static let background = adaptive(light: 0xF7F7FB, dark: 0x18191F)
  static let surface = adaptive(light: 0xFFFFFF, dark: 0x24262F)
  static let secondarySurface = adaptive(light: 0xEEEFF6, dark: 0x2C2E39)
  static let accent = adaptive(light: 0x6D5CE8, dark: 0xAC9EFF)
  static let border = adaptive(light: 0xDADBE8, dark: 0x40434F)
  static let success = adaptive(light: 0x167A59, dark: 0x7EDCBA)
  static let warning = adaptive(light: 0x96600B, dark: 0xF2C57E)
  static let destructive = adaptive(light: 0xB92E40, dark: 0xFF8C9B)

  // Filled actions keep darker violet in both appearances so their white labels
  // retain contrast; the lighter accent is for text on dark surfaces.
  static let primaryActionFill = Color(red: 0.40, green: 0.33, blue: 0.86)
  static let primaryActionHover = Color(red: 0.36, green: 0.29, blue: 0.81)
  static let primaryActionPressed = Color(red: 0.32, green: 0.25, blue: 0.75)

  static let hoverFill = accent.opacity(0.07)
  static let pressedFill = accent.opacity(0.13)
  static let selectedFill = accent.opacity(0.12)
  static let accentSelectionFill = accent.opacity(0.14)
  static let accentSelectionText = Color(nsColor: .labelColor)
  static let focusStroke = accent
  static let focusStrokeWidth: CGFloat = 1.5
  static let focusFill = accent.opacity(0.09)

  /// Stable between processes and renames. Swift's randomized hashValue must
  /// not be used for a tag's visual identity. No persistent field is needed.
  static func tagColor(for id: UUID) -> Color {
    let palette: [Color] = [
      accent,
      adaptive(light: 0x238067, dark: 0x80D9BC),
      adaptive(light: 0xAD671E, dark: 0xF2BC83),
      adaptive(light: 0x3678B6, dark: 0x8EC6F4),
    ]
    let value = id.uuidString.utf8.reduce(UInt64(1_469_598_103_934_665_603)) {
      ($0 ^ UInt64($1)) &* 1_099_511_628_211
    }
    return palette[Int(value % UInt64(palette.count))]
  }

  private static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        return NSColor(
          srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
          green: CGFloat((value >> 8) & 0xFF) / 255,
          blue: CGFloat(value & 0xFF) / 255,
          alpha: 1)
      })
  }

  // Color and opacity do not need springs. Spatial transitions have explicit
  // zero bounce; only sorting has a small physical overshoot. snappy with
  // extraBounce: 0 still includes the preset's bounce and is not a substitute.
  static var hoverAnimation: Animation { .easeOut(duration: 0.12) }
  static var pressAnimation: Animation { .easeOut(duration: 0.09) }
  static var selectionAnimation: Animation { .spring(duration: 0.18, bounce: 0) }
  static var tabSwitchAnimation: Animation { .spring(duration: 0.18, bounce: 0) }
  static var composerAnimation: Animation { .spring(duration: 0.20, bounce: 0) }
  static var pageTransitionAnimation: Animation { .spring(duration: 0.20, bounce: 0) }
  static var completionAnimation: Animation { .easeOut(duration: 0.18) }
  static var reorderAnimation: Animation { .spring(duration: 0.24, bounce: 0.08) }
  static var insertionAnimation: Animation { .easeOut(duration: 0.18) }
  static var reducedMotionAnimation: Animation { .easeOut(duration: 0.10) }
}
