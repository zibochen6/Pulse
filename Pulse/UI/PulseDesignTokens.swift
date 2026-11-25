import AppKit
import SwiftUI

private struct PulseReduceMotionOverrideKey: EnvironmentKey {
  static let defaultValue: Bool? = nil
}

private struct PulseNativeBackdropKey: EnvironmentKey {
  static let defaultValue = false
}

private struct PulsePaperOpacityKey: EnvironmentKey {
  static let defaultValue = 1.0
}

extension EnvironmentValues {
  var pulseReduceMotionOverride: Bool? {
    get { self[PulseReduceMotionOverrideKey.self] }
    set { self[PulseReduceMotionOverrideKey.self] = newValue }
  }

  var pulseReduceMotion: Bool { pulseReduceMotionOverride ?? accessibilityReduceMotion }

  var pulseHasNativeBackdrop: Bool {
    get { self[PulseNativeBackdropKey.self] }
    set { self[PulseNativeBackdropKey.self] = newValue }
  }

  var pulsePaperOpacity: Double {
    get { self[PulsePaperOpacityKey.self] }
    set { self[PulsePaperOpacityKey.self] = newValue }
  }
}

/// Shared visual and motion vocabulary for the menu-bar surface and Settings.
/// Cards and controls retain their adaptive colors over the window backdrop.
enum PulseDesignTokens {
  static let label: CGFloat = 14
  static let footnote: CGFloat = 13
  static let caption: CGFloat = 12
  static let toolbarTitle: CGFloat = 18
  static let displayTitle: CGFloat = 30

  static let cornerSmall: CGFloat = 8
  static let cornerMedium: CGFloat = 10
  static let cornerLarge: CGFloat = 15
  static let gap: CGFloat = 8
  static let contentInset: CGFloat = 16
  static let brandMarkSize: CGFloat = 28
  static let taskRowHeight: CGFloat = 36

  static let background = adaptive(light: 0xFFFFFF, dark: 0x232427)

  static func paperOpacity(transparencyPercent: Int) -> Double {
    // The window tint and each overlying paper card share the transmission.
    // Through both layers, their transmissions multiply to the selected value.
    1 - sqrt(Double(transparencyPercent) / 100)
  }
  static let surface = adaptive(light: 0xFFFFFF, dark: 0x292A26)
  static let secondarySurface = adaptive(light: 0xF2F2EF, dark: 0x30312E)
  static let ink = adaptive(light: 0x242421, dark: 0xF1F2E9)
  static let muted = adaptive(light: 0x62645B, dark: 0xC2C4B8)
  static let border = adaptive(light: 0xE4E5DC, dark: 0x45473F)
  static let accent = adaptive(light: 0x496D26, dark: 0xC6E69B)
  static let success = adaptive(light: 0x347128, dark: 0xA8D782)
  static let warning = adaptive(light: 0x96600B, dark: 0xF2C57E)
  static let destructive = adaptive(light: 0xB92E40, dark: 0xFF8C9B)

  static let taskPaper = adaptive(light: 0xE5E7FA, dark: 0x363447)
  static let taskFold = adaptive(light: 0xA3A7C2, dark: 0x68617F)
  static let rosePaper = adaptive(light: 0xF9DCE6, dark: 0x48333B)
  static let skyPaper = adaptive(light: 0xD9EFF9, dark: 0x293E49)
  static let mintPaper = adaptive(light: 0xE0EFCF, dark: 0x343F30)
  static let butterPaper = adaptive(light: 0xFFF3CB, dark: 0x443D2B)

  static let primaryActionFill = adaptive(light: 0xCCEAA0, dark: 0xC6E69B)
  static let primaryActionHover = adaptive(light: 0xC2E490, dark: 0xD1EEAD)
  static let primaryActionPressed = adaptive(light: 0xB3D982, dark: 0xB7D68B)
  static let actionInk = adaptive(light: 0x25281E, dark: 0x25281E)

  static let hoverFill = ink.opacity(0.07)
  static let pressedFill = ink.opacity(0.14)
  static let selectedFill = adaptive(light: 0xCCEAA0, dark: 0x405332)
  static let focusStroke = adaptive(light: 0x665098, dark: 0xD2C5F4)
  static let focusFill = focusStroke.opacity(0.10)

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

  // Color and opacity ease out. Spatial changes settle without overshooting.
  static let contentFadeDuration: TimeInterval = 0.14
  static let busyFeedbackDelay: Duration = .milliseconds(150)
  static var hoverAnimation: Animation { .easeOut(duration: 0.12) }
  static var releaseAnimation: Animation { .easeOut(duration: 0.09) }
  static var feedbackAnimation: Animation { .easeOut(duration: contentFadeDuration) }
  static var composerAnimation: Animation { .spring(duration: 0.20, bounce: 0) }
  static var completionAnimation: Animation { .easeOut(duration: 0.18) }
  static var tabSwitchAnimation: Animation { composerAnimation }
  static var reorderAnimation: Animation { composerAnimation }
}
