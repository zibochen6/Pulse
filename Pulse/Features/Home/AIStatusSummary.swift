import AppKit
import SwiftUI

/// A glanceable readout of the same state used by the menu bar item.
struct AIStatusSummary: View {
  let state: UsageRefreshState
  let onOpenUsage: () -> Void

  var body: some View {
    Button(action: onOpenUsage) {
      HStack(spacing: 5) {
        codexIcon
        Text(UsageMenuFormatter.title(for: state))
          .font(.subheadline.weight(.medium))
          .monospacedDigit()
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .padding(.horizontal, 8)
      .frame(height: 28)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help("Open Codex usage details")
    .accessibilityLabel("Codex usage: \(UsageMenuFormatter.title(for: state)). Open details")
    .accessibilityIdentifier("openUsageButton")
  }

  private var codexIcon: some View {
    Group {
      if let url = Bundle.main.url(forResource: "CodexMenuIcon", withExtension: "png"),
        let image = NSImage(contentsOf: url)
      {
        Image(nsImage: image)
          .resizable()
          .renderingMode(.template)
          .scaledToFit()
      } else {
        Image(systemName: "sparkle")
      }
    }
    .frame(width: 16, height: 16)
    .foregroundStyle(.secondary)
  }
}
