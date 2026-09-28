import SwiftUI

struct UsageView: View {
  @ObservedObject var usage: UsageController

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
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
        if snapshot.quotaWindows.count == 1, let window = snapshot.quotaWindows.first {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(window.remainingPercent.map { "\($0)%" } ?? "--")
              .font(.system(size: 34, weight: .semibold, design: .rounded))
              .monospacedDigit()
            Text("remaining")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Text(window.displayName)
            .font(.subheadline)
            .foregroundStyle(.secondary)
          resetText(for: window)
        } else {
          ForEach(Array(snapshot.quotaWindows.enumerated()), id: \.offset) { index, window in
            if index > 0 { Divider() }
            HStack(alignment: .firstTextBaseline) {
              Text(window.displayName)
                .font(.subheadline)
              Spacer()
              Text(window.remainingPercent.map { "\($0)%" } ?? "--")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            }
            resetText(for: window)
          }
        }
        Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func resetText(for window: QuotaWindow) -> some View {
    Text(
      window.resetsAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" }
        ?? "Reset time unavailable"
    )
    .font(.caption)
    .foregroundStyle(.secondary)
  }
}
