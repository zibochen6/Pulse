import SwiftUI

struct UsageView: View {
  @ObservedObject var usage: UsageController

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Codex")
          .fontWeight(.semibold)
        Spacer()
        Button("Refresh") { usage.requestRefresh() }
          .disabled(isLoading)
          .accessibilityIdentifier("refreshCodexUsageButton")
      }

      switch usage.state {
      case .loading:
        Label("Checking usage…", systemImage: "arrow.triangle.2.circlepath")
          .foregroundStyle(.secondary)
      case .unavailable(let message):
        Label(message, systemImage: "minus.circle")
          .foregroundStyle(.secondary)
      case .failure(let message):
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
      case .success(let snapshot):
        ForEach(Array(snapshot.quotaWindows.enumerated()), id: \.offset) { _, window in
          VStack(alignment: .leading, spacing: 3) {
            HStack {
              Text(window.displayName)
              Spacer()
              Text(window.remainingPercent.map { "\($0)% left" } ?? "Quota unavailable")
                .monospacedDigit()
            }
            if let reset = window.resetsAt {
              Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
              Text("Reset time unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .font(.subheadline)
  }

  private var isLoading: Bool {
    if case .loading = usage.state { return true }
    return false
  }
}
