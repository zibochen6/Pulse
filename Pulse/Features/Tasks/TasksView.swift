import SwiftUI

/// A list-shaped task surface; real Markdown rows can replace the disconnected row later.
struct TasksView: View {
  let onConnect: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Tasks")
          .font(.headline)
        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)

      Divider()

      HStack {
        Text("Obsidian not connected")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(.horizontal, 20)
      .frame(height: 52)

      Spacer(minLength: 0)

      Divider()

      Button(action: onConnect) {
        HStack(spacing: 9) {
          Image(systemName: "link.circle.fill")
            .font(.system(size: 18))
            .foregroundStyle(.secondary)
          Text("Connect Obsidian")
            .font(.subheadline.weight(.medium))
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("connectObsidianButton")
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
  }
}
