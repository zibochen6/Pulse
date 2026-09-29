import SwiftUI

/// The compact, read-only task surface for an already configured Apex Dashboard.
struct TasksView: View {
  @ObservedObject var tasks: DashboardTaskController
  let onConfigure: () -> Void
  let onOpenTask: (DashboardTask) -> Bool

  @State private var selectedColumnTitle: String?
  @State private var openErrorMessage: String?

  var body: some View {
    content
  }

  @ViewBuilder
  private var content: some View {
    switch tasks.state {
    case .notConfigured:
      statusContent(
        title: "Obsidian Dashboard not connected",
        message: "Choose an Apex Dashboard file in Settings to see its tasks.",
        actionTitle: "Connect in Settings",
        action: onConfigure
      )
    case .loading:
      VStack(spacing: 10) {
        ProgressView()
        Text("Loading Dashboard")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .fileMissing:
      statusContent(
        title: "Dashboard file unavailable",
        message: "The selected file was moved or deleted. Choose it again in Settings.",
        actionTitle: "Open Settings",
        action: onConfigure
      )
    case .permissionDenied:
      statusContent(
        title: "Cannot read Dashboard",
        message: "Pulse no longer has permission to read the selected file.",
        actionTitle: "Open Settings",
        action: onConfigure
      )
    case .readError(let message):
      statusContent(title: "Cannot read Dashboard", message: message, actionTitle: "Try Again") {
        tasks.requestRefresh()
      }
    case .parseError(let message):
      statusContent(title: "Cannot parse Dashboard", message: message, actionTitle: "Try Again") {
        tasks.requestRefresh()
      }
    case .loaded(let dashboard):
      dashboardContent(dashboard)
    }
  }

  private func dashboardContent(_ dashboard: Dashboard) -> some View {
    VStack(spacing: 0) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
          ForEach(dashboard.columns) { column in
            TaskColumnTab(
              title: column.title,
              isSelected: selectedColumn(dashboard)?.title == column.title
            ) {
              selectedColumnTitle = column.title
            }
            .accessibilityIdentifier("dashboardColumnTab.\(column.sourceOrder)")
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
      }

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 9) {
          if let column = selectedColumn(dashboard) {
            if column.cards.isEmpty {
              Text("No tasks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
              ForEach(column.cards) { card in
                cardContent(card)
              }
            }
          }
          if let openErrorMessage {
            Text(openErrorMessage)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .onAppear { selectedColumnTitle = nil }
    .onChange(of: dashboard.fileURL) { _ in selectedColumnTitle = nil }
  }

  private func cardContent(_ card: DashboardCard) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(card.title)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.leading, 1)
      ForEach(card.tasks) { task in
        TaskRow(task: task) {
          openErrorMessage = onOpenTask(task) ? nil : "Obsidian could not open this Dashboard file."
        }
        .accessibilityLabel("\(task.completed ? "Completed" : "Open") task: \(task.text)")
        .accessibilityIdentifier("dashboardTask.\(task.lineNumber)")
      }
    }
  }

  private func selectedColumn(_ dashboard: Dashboard) -> DashboardColumn? {
    dashboard.columns.first(where: { $0.title == selectedColumnTitle }) ?? dashboard.columns.first
  }

  private func statusContent(
    title: String, message: String, actionTitle: String, action: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.subheadline.weight(.medium))
      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(actionTitle, action: action)
        .buttonStyle(.borderless)
        .font(.caption.weight(.medium))
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct TaskColumnTab: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? .primary : .secondary)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(tabBackground, in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }

  private var tabBackground: Color {
    if isSelected {
      return Color(nsColor: .selectedControlColor).opacity(0.16)
    }
    return isHovered ? Color(nsColor: .controlBackgroundColor) : .clear
  }
}

private struct TaskRow: View {
  let task: DashboardTask
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 15, weight: .medium))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(
            task.completed
              ? Color(nsColor: .tertiaryLabelColor)
              : Color(nsColor: .secondaryLabelColor).opacity(0.8)
          )
          .padding(.top, 2)
        Text(task.text)
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(
            task.completed
              ? Color(nsColor: .secondaryLabelColor).opacity(0.7)
              : Color.primary
          )
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .frame(minHeight: 30)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(TaskRowButtonStyle(isHovered: isHovered))
    .onHover { isHovered = $0 }
  }
}

private struct TaskRowButtonStyle: ButtonStyle {
  let isHovered: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        (isHovered || configuration.isPressed)
          ? Color(nsColor: .quaternaryLabelColor)
            .opacity(configuration.isPressed ? 0.28 : 0.16)
          : .clear,
        in: RoundedRectangle(cornerRadius: 6)
      )
      .opacity(configuration.isPressed ? 0.72 : 1)
      .animation(.easeOut(duration: 0.12), value: isHovered)
  }
}
