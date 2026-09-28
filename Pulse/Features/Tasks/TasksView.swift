import SwiftUI

struct TasksView: View {
  let onConnect: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "checklist")
          .foregroundStyle(.secondary)
        Text("Obsidian is not connected")
          .font(.subheadline.weight(.medium))
      }
      Text("Your tasks will appear here after connection is available.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button("Connect Obsidian", action: onConnect)
        .buttonStyle(.borderless)
        .font(.caption.weight(.medium))
        .accessibilityIdentifier("connectObsidianButton")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
