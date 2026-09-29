import SwiftUI

/// The compact, read-only task surface for an already configured Apex Dashboard.
struct TasksView: View {
  @ObservedObject var tasks: DashboardTaskController
  let onConfigure: () -> Void
  let onOpenTask: (DashboardTask) -> Bool

  @State private var selectedColumnTitle: String?
  @State private var openErrorMessage: String?

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Text("Tasks")
        .font(.headline)
      Spacer()
      Button {
        tasks.requestRefresh()
      } label: {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 12, weight: .medium))
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.borderless)
      .disabled(tasks.isRefreshing || !tasks.configuration.hasDashboardSelection)
      .help("Refresh Dashboard")
      .accessibilityLabel("Refresh Dashboard")
      .accessibilityIdentifier("refreshDashboardButton")
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
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
        HStack(spacing: 6) {
          ForEach(dashboard.columns) { column in
            Button(column.title) {
              selectedColumnTitle = column.title
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(selectedColumn(dashboard)?.title == column.title ? .semibold : .regular))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
              selectedColumn(dashboard)?.title == column.title
                ? Color(nsColor: .selectedControlColor).opacity(0.16) : .clear,
              in: Capsule()
            )
            .accessibilityIdentifier("dashboardColumnTab.\(column.sourceOrder)")
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
      }

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
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
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .onAppear { selectedColumnTitle = nil }
    .onChange(of: dashboard.fileURL) { _ in selectedColumnTitle = nil }
  }

  private func cardContent(_ card: DashboardCard) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(card.title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      ForEach(card.tasks) { task in
        Button {
          openErrorMessage = onOpenTask(task) ? nil : "Obsidian could not open this Dashboard file."
        } label: {
          HStack(alignment: .top, spacing: 9) {
            Image(systemName: task.completed ? "checkmark.square" : "square")
              .font(.system(size: 15))
              .foregroundStyle(task.completed ? .tertiary : .secondary)
            Text(task.text)
              .font(.subheadline)
              .strikethrough(task.completed, color: .secondary)
              .foregroundStyle(task.completed ? .secondary : .primary)
              .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
          }
          .contentShape(Rectangle())
          .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
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
