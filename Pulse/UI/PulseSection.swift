import AppKit
import SwiftUI

struct PulseSection<Content: View>: View {
  let title: String
  let symbol: String
  var paper = PulseDesignTokens.surface
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(PulseDesignTokens.ink)
          .frame(width: 24, height: 24)
          .background(
            PulseDesignTokens.secondarySurface, in: Circle())
        Text(LocalizedStringKey(title))
          .font(.system(size: PulseDesignTokens.toolbarTitle, weight: .semibold))
          .pulseContentFeedback(title)
      }
      content
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .pulsePaper(paper)
  }
}

extension View {
  func pulsePaper(
    _ fill: Color = PulseDesignTokens.surface, radius: CGFloat = PulseDesignTokens.cornerLarge
  ) -> some View {
    modifier(PulsePaper(fill: fill, radius: radius))
  }
}

private struct PulsePaper: ViewModifier {
  let fill: Color
  let radius: CGFloat
  @Environment(\.pulsePaperOpacity) private var opacity

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius)
    content.background(fill.opacity(opacity), in: shape).overlay {
      shape.strokeBorder(PulseDesignTokens.border, lineWidth: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }
}

struct PulseBrandMark: View {
  var size: CGFloat = PulseDesignTokens.brandMarkSize

  var body: some View {
    Image(systemName: "waveform.path")
      .font(.system(size: size * 0.48, weight: .semibold))
      .foregroundStyle(PulseDesignTokens.ink)
      .frame(width: size, height: size)
      .background(PulseDesignTokens.surface, in: Circle())
      .overlay { Circle().strokeBorder(PulseDesignTokens.ink, lineWidth: 1) }
      .accessibilityHidden(true)
  }
}
