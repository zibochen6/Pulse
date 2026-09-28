import SwiftUI

struct TasksView: View {
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "checkmark.circle")
        .font(.system(size: 29, weight: .light))
        .foregroundStyle(.secondary)
      Text("Obsidian is not connected")
        .font(.subheadline.weight(.semibold))
      Text("Your tasks will appear here after connection is available.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
