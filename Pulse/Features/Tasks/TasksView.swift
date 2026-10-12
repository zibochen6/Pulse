import SwiftUI

/// The compact task surface. Views dispatch intents; the file service owns writes.
struct TasksView: View {
  @ObservedObject var tasks: DashboardTaskController
  @ObservedObject var presentation: DashboardTaskPresentation
  let onConfigure: () -> Void
  let onOpenTask: (DashboardTask) -> Bool
  var onUseBuiltInTasks: (() -> Void)?
  var onEditingChanged: (Bool) -> Void = { _ in }

  @State private var openErrorMessage: String?

  var body: some View {
    taskSurface
      .onAppear {
        presentation.reconcileSelection(tasks.selectionGeneration)
        if case .loaded(let dashboard) = tasks.state {
          presentation.reconcileFile(dashboard.fileURL)
        } else if case .notConfigured = tasks.state {
          presentation.draft = nil
        }
        onEditingChanged(presentation.isEditing)
      }
      .onChange(of: presentation.isEditing) { onEditingChanged($0) }
      .onDisappear { onEditingChanged(false) }
      .onChange(of: tasks.selectionGeneration) { presentation.reconcileSelection($0) }
      .onChange(of: tasks.state) { state in
        if case .loaded(let dashboard) = state {
          presentation.reconcileFile(dashboard.fileURL)
        } else if case .notConfigured = state {
          presentation.draft = nil
        }
      }
  }

  private var taskSurface: some View {
    VStack(spacing: 0) {
      if let failure = tasks.saveFailure {
        PulseErrorBanner(
          message: failure.message,
          accessibilityIdentifier: "dashboardSaveError"
        ) {
          if failure.needsReselection {
            Button("Choose file in Settings", action: onConfigure)
          } else {
            Button("Retry save") { tasks.retrySave() }
              .disabled(tasks.pendingTaskIDs.contains(failure.task.id))
            Button("Refresh") { tasks.requestRefresh() }
          }
          Button("Dismiss") { tasks.dismissSaveFailure() }
        }
        Divider()
      }
      content
    }
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
      if let onUseBuiltInTasks {
        Button("Use built-in tasks", action: onUseBuiltInTasks)
          .buttonStyle(.borderless)
          .font(.subheadline.weight(.medium))
          .accessibilityIdentifier("useBuiltInTasksButton")
          .padding(.horizontal, 20)
          .padding(.bottom, 16)
      }
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
            PulsePillTab(
              title: column.title,
              isSelected: selectedColumn(dashboard)?.title == column.title,
              action: {
                presentation.selectedColumnTitle = column.title
              }
            )
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
            let visibleCards = column.cards.filter { card in
              card.tasks.contains { !$0.completed }
            }
            if visibleCards.isEmpty {
              Text("No unfinished tasks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)
            } else {
              ForEach(visibleCards) { card in
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
      Divider()
      if let draft = presentation.draft {
        DashboardTaskEditor(
          controller: tasks, presentation: presentation,
          draft: Binding(get: { presentation.draft ?? draft }, set: { presentation.draft = $0 }),
          onConfigure: onConfigure)
      } else {
        Button {
          tasks.dismissAddFailure()
          presentation.beginAdding(in: dashboard)
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
            Text("Add task")
            Spacer()
          }
          .frame(maxWidth: .infinity, minHeight: 22)
        }
        .buttonStyle(PulseActionButtonStyle())
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .accessibilityIdentifier("addDashboardTaskButton")
      }
    }
    .onChange(of: dashboard.fileURL) { _ in
      presentation.selectedColumnTitle = nil
    }
  }

  private func cardContent(_ card: DashboardCard) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(card.title)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.leading, 1)
      ForEach(card.tasks.filter { !$0.completed }) { task in
        taskRow(task)
      }
    }
  }

  private func taskRow(_ task: DashboardTask) -> some View {
    DashboardTaskRow(
      task: task,
      isPending: tasks.pendingTaskIDs.contains(task.id),
      onToggle: { tasks.setCompleted(!task.completed, task: task) },
      onOpen: {
        openErrorMessage = onOpenTask(task) ? nil : "Obsidian could not open this Dashboard file."
      })
  }

  private func selectedColumn(_ dashboard: Dashboard) -> DashboardColumn? {
    dashboard.columns.first(where: { $0.title == presentation.selectedColumnTitle })
      ?? dashboard.columns.first
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

struct DashboardTaskRow: View {
  let task: DashboardTask
  let isPending: Bool
  let onToggle: () -> Void
  let onOpen: () -> Void

  @State private var isHovered = false

  var body: some View {
    HStack(alignment: .top, spacing: 2) {
      Button(action: onToggle) {
        Group {
          if isPending {
            ProgressView().controlSize(.mini)
          } else {
            Image(
              systemName: task.canToggle
                ? (task.completed ? "checkmark.circle.fill" : "circle") : "minus.circle"
            )
            .font(.system(size: 15, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
              task.completed
                ? Color(nsColor: .secondaryLabelColor)
                : Color(nsColor: .secondaryLabelColor).opacity(0.8)
            )
          }
        }
        .padding(.top, 2)
        .frame(width: 28, height: 30, alignment: .top)
        .contentShape(Rectangle())
      }
      .buttonStyle(PulseRowButtonStyle(isHovered: isHovered))
      .disabled(isPending || !task.canToggle)
      .help(
        task.canToggle
          ? (task.completed ? "Mark incomplete" : "Mark complete")
          : "Special task state; edit in Obsidian"
      )
      .accessibilityLabel(
        "\(task.canToggle ? (task.completed ? "Mark incomplete" : "Mark complete") : "Read-only task"): \(task.text)"
      )
      .accessibilityValue(
        isPending
          ? "Saving"
          : (task.canToggle
            ? (task.completed ? "Completed" : "Not completed") : "Read-only special state")
      )
      .accessibilityIdentifier("dashboardCheckbox.\(task.lineNumber)")

      Button(action: onOpen) {
        Text(task.text)
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(
            task.completed
              ? Color(nsColor: .secondaryLabelColor).opacity(0.7)
              : Color.primary
          )
          .strikethrough(
            task.completed, pattern: .solid, color: Color(nsColor: .tertiaryLabelColor)
          )
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
          .contentShape(Rectangle())
      }
      .buttonStyle(PulseRowButtonStyle(isHovered: isHovered))
      .accessibilityLabel("Open in Obsidian: \(task.text)")
      .accessibilityIdentifier("dashboardTask.\(task.lineNumber)")
    }
    .padding(.leading, CGFloat((task.source?.indentation ?? 0) / 4) * 10)
    .onHover { isHovered = $0 }
  }
}
