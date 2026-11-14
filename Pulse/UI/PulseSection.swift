import AppKit
import SwiftUI

struct PulseSection<Content: View>: View {
  let title: String
  let symbol: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(PulseDesignTokens.accent)
          .frame(width: 24, height: 24)
          .background(
            PulseDesignTokens.accent.opacity(0.09),
            in: RoundedRectangle(cornerRadius: PulseDesignTokens.cornerSmall))
        Text(LocalizedStringKey(title))
          .font(.system(size: PulseDesignTokens.label, weight: .semibold))
      }
      content
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      PulseDesignTokens.surface,
      in: RoundedRectangle(cornerRadius: PulseDesignTokens.cornerLarge)
    )
    .overlay {
      RoundedRectangle(cornerRadius: PulseDesignTokens.cornerLarge)
        .strokeBorder(PulseDesignTokens.border.opacity(0.55), lineWidth: 0.7)
    }
  }
}
