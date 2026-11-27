import AppKit
import SwiftUI

struct AntigravityProviderIcon: View {
  let size: CGFloat

  private static let artwork = Bundle.main.url(
    forResource: "AntigravityColorIcon", withExtension: "png"
  ).flatMap { NSImage(contentsOf: $0) }

  var body: some View {
    Group {
      if let artwork = Self.artwork {
        Image(nsImage: artwork).resizable().scaledToFit()
      } else {
        Image(systemName: "sparkle").foregroundStyle(Color.accentColor)
      }
    }
    .padding(size * 0.12)
    .frame(width: size, height: size)
    .background(.white, in: RoundedRectangle(cornerRadius: size * 0.24))
    .accessibilityHidden(true)
  }
}
