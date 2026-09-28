import AppKit
import SwiftUI

/// The color Codex mark used inside Pulse's popover.
///
/// macOS status bar artwork remains a separate template image so it can adopt
/// the system's light and dark menu bar appearance.
struct CodexProviderIcon: View {
  let size: CGFloat

  var body: some View {
    Group {
      if let url = Bundle.main.url(forResource: "CodexColorIcon", withExtension: "png"),
        let image = NSImage(contentsOf: url)
      {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: "sparkle")
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: size, height: size)
  }
}
