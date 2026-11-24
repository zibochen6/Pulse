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
    let shape = RoundedRectangle(cornerRadius: radius)
    return self.background(fill, in: shape).overlay {
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

struct PulseMarkedTitle: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.system(size: PulseDesignTokens.displayTitle, weight: .bold))
      .tracking(-0.8)
      .foregroundStyle(PulseDesignTokens.ink)
      .background(alignment: .bottom) {
        Capsule()
          .fill(PulseDesignTokens.marker)
          .frame(height: 5)
          .rotationEffect(.degrees(-3))
          .offset(y: -3)
          .accessibilityHidden(true)
      }
      .accessibilityAddTraits(.isHeader)
  }
}
