import AppKit
import SwiftUI

struct UsageView: View {
  @ObservedObject var usage: UsageController
  let onAddProvider: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 8) {
        codexIcon
        Text("Codex")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Button {
          usage.requestRefresh()
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .disabled(usage.isRefreshing)
        .help(usage.isRefreshing ? "Refreshing Codex usage" : "Refresh Codex usage")
        .accessibilityLabel("Refresh Codex usage")
        .accessibilityIdentifier("refreshCodexUsageButton")
      }

      switch usage.state {
      case .loading:
        Text("Checking usage…")
          .foregroundStyle(.secondary)
      case .unavailable(let message):
        Label(message, systemImage: "minus.circle")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      case .failure(let message):
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      case .success(let snapshot):
        ForEach(Array(snapshot.quotaWindows.enumerated()), id: \.offset) { index, window in
          if index > 0 { Divider() }
          quotaRow(window)
        }
        Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      Divider()
      HStack(spacing: 8) {
        Text("No other providers connected")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer(minLength: 4)
        Button("Add Provider", action: onAddProvider)
          .buttonStyle(.borderless)
          .font(.caption.weight(.medium))
          .accessibilityIdentifier("addProviderButton")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func quotaRow(_ window: QuotaWindow) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .firstTextBaseline) {
        Text(window.displayName)
          .font(.subheadline)
        Spacer()
        Text(window.remainingPercent.map { "\($0)%" } ?? "--")
          .font(.system(size: 20, weight: .semibold, design: .rounded))
          .monospacedDigit()
      }
      Text(
        window.resetsAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" }
          ?? "Reset time unavailable"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
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
