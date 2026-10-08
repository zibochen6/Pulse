import SwiftUI

/// Kept above page navigation so an accidental popover close does not discard a draft.
@MainActor
final class LocalTaskPresentation: ObservableObject {
  @Published var selectedFilter: LocalTaskFilter = .all
  @Published var draft: LocalTaskDraft?

  var isEditing: Bool { draft != nil }

  func beginAddingTask() {
    let initialTags: Set<UUID>
    if case .tag(let tagID) = selectedFilter {
      initialTags = [tagID]
    } else {
      initialTags = []
    }
    draft = LocalTaskDraft(tagIDs: initialTags)
  }

  func beginEditingTask(_ task: LocalTask) {
    // Existing rows stay visible during inline creation; an incidental text
    // click must not replace that unsaved or pending creation intent.
    guard draft == nil else { return }
    draft = LocalTaskDraft(taskID: task.id, text: task.text, tagIDs: task.tagIDs)
  }

  func finishDraft(id: UUID) {
    guard draft?.creationID == id else { return }
    draft = nil
  }

  func didCreate(id: UUID, task: LocalTask?) {
    guard draft?.creationID == id else { return }
    if let task {
      switch selectedFilter {
      case .all: break
      case .untagged:
        if !task.tagIDs.isEmpty { selectedFilter = .all }
      case .tag(let tagID):
        if !task.tagIDs.contains(tagID) { selectedFilter = .all }
      }
    }
    draft = nil
  }

  func reconcileTags(_ tags: [TaskTag]) {
    let availableIDs = Set(tags.map(\.id))
    if case .tag(let selected) = selectedFilter, !availableIDs.contains(selected) {
      selectedFilter = .all
    }
    if var currentDraft = draft {
      let remainingIDs = currentDraft.tagIDs.intersection(availableIDs)
      if remainingIDs != currentDraft.tagIDs {
        currentDraft.tagIDs = remainingIDs
        draft = currentDraft
      }
    }
  }
}

struct LocalTaskDraft {
  let creationID = UUID()
  var taskID: UUID?
  var text = ""
  var tagIDs: Set<UUID> = []
  var newTagNames: [String] = []
  var newTagText = ""
  var confirmsDeletion = false

  /// Both the Add-tag button and task submission consume this field identically.
  /// Selecting an already-staged tag is a no-op, not an error that blocks Save.
  mutating func acceptPendingTag(availableTags: [TaskTag]) {
    let name = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    let canonical = name.lowercased()
    if let existing = availableTags.first(where: {
      $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == canonical
    }) {
      tagIDs.insert(existing.id)
    } else if !newTagNames.contains(where: {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == canonical
    }) {
      newTagNames.append(name)
    }
    newTagText = ""
  }
}

/// Local tasks and Apex tasks have separate controllers and storage.
@MainActor
struct LocalTasksView: View {
  @ObservedObject var controller: LocalTaskController
  @ObservedObject var presentation: LocalTaskPresentation
  let onEditingChanged: (Bool) -> Void

  var body: some View {
    Group {
      if let draft = presentation.draft, draft.taskID != nil {
        LocalTaskEditor(
          controller: controller,
          draft: Binding(
            get: { presentation.draft ?? draft },
            set: { presentation.draft = $0 }
          ),
          onClose: { presentation.finishDraft(id: draft.creationID) }
        )
      } else {
        taskList
      }
    }
    .onAppear {
      if let tags = controller.document?.tags { presentation.reconcileTags(tags) }
      onEditingChanged(presentation.isEditing)
    }
    .task {
      if controller.document == nil { await controller.refresh() }
    }
    .onChange(of: presentation.isEditing) { onEditingChanged($0) }
    .onDisappear { onEditingChanged(false) }
    .onChange(of: controller.document?.tags) { tags in
      if let tags { presentation.reconcileTags(tags) }
    }
  }

  private var taskList: some View {
    VStack(spacing: 0) {
      if let document = controller.document {
        filters(document.tags)
        Divider()
      }
      let completionFailure =
        controller.document?.tasks.compactMap {
          controller.completionFailures[$0.id]
        }.first
        ?? controller.completionFailures.sorted {
          $0.key.uuidString < $1.key.uuidString
        }.first?.value
      if let completionFailure {
        errorContent(
          completionFailure.message,
          onRetry: {
            controller.setCompleted(completionFailure.completed, taskID: completionFailure.taskID)
          },
          onDismiss: {
            controller.dismissCompletionFailure(taskID: completionFailure.taskID)
          }
        )
        Divider()
      } else if let errorMessage = controller.errorMessage,
        presentation.draft?.taskID != nil || presentation.draft == nil
      {
        errorContent(
          errorMessage,
          onRetry: { Task { await controller.refresh() } },
          onDismiss: { controller.dismissError() }
        )
        Divider()
      }

      if controller.document != nil {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            let tasks = controller.tasks(matching: presentation.selectedFilter)
            let incompleteTasks = tasks.filter { !$0.completed }
            if incompleteTasks.isEmpty {
              Text(
                tasks.isEmpty
                  ? (presentation.selectedFilter == .all
                    ? "No tasks yet" : "No tasks in this category")
                  : "No unfinished tasks"
              )
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
              .padding(.vertical, 12)
            }
            ForEach(incompleteTasks) { task in
              taskRow(task)
            }
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("localTaskList")
      } else if controller.isLoading {
        ProgressView("Loading tasks")
          .font(.caption)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Text("Tasks could not be loaded. Your saved file has not been cleared.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(14)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }

      if controller.document != nil {
        Divider()
        if let draft = presentation.draft, draft.taskID == nil {
          LocalTaskInlineComposer(
            controller: controller, presentation: presentation,
            draft: Binding(
              get: { presentation.draft ?? draft }, set: { presentation.draft = $0 }))
        } else {
          Button {
            controller.dismissError()
            presentation.beginAddingTask()
          } label: {
            HStack(spacing: 8) {
              Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
              Text("Add task")
                .font(.system(size: 14))
              Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 16)
          .padding(.vertical, 6)
          .accessibilityIdentifier("addLocalTaskButton")
        }
      }
    }
  }

  private func taskRow(_ task: LocalTask) -> some View {
    LocalTaskRow(
      task: task,
      isPending: controller.pendingTaskIDs.contains(task.id),
      isEditingEnabled: presentation.draft == nil,
      onToggle: { controller.setCompleted(!task.completed, taskID: task.id) },
      onEdit: { presentation.beginEditingTask(task) }
    )
  }

  private func filters(_ tags: [TaskTag]) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        filterButton("All", filter: .all, identifier: "all")
        filterButton("Untagged", filter: .untagged, identifier: "untagged")
        ForEach(tags) { tag in
          filterButton(tag.name, filter: .tag(tag.id), identifier: tag.id.uuidString)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 3)
    }
  }

  private func filterButton(
    _ title: String, filter: LocalTaskFilter, identifier: String
  ) -> some View {
    LocalTaskFilterButton(
      title: title,
      isSelected: presentation.selectedFilter == filter,
      action: { presentation.selectedFilter = filter }
    )
    .accessibilityIdentifier("localTaskFilter.\(identifier)")
  }

  private func errorContent(
    _ message: String, onRetry: @escaping () -> Void, onDismiss: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(message)
        .font(.caption)
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("Try again", action: onRetry)
          .disabled(controller.isSaving || controller.isLoading)
        Spacer()
        Button("Dismiss", action: onDismiss)
      }
      .buttonStyle(.borderless)
      .font(.caption)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 6)
    .accessibilityIdentifier("localTaskError")
  }

}

/// New tasks are composed under the existing list. Existing-task edits retain
/// their separate editor, including its deletion confirmation.
@MainActor
private struct LocalTaskInlineComposer: View {
  @ObservedObject var controller: LocalTaskController
  @ObservedObject var presentation: LocalTaskPresentation
  @Binding var draft: LocalTaskDraft
  @FocusState private var textFocused: Bool
  @State private var isSubmitting = false

  private var isBusy: Bool { isSubmitting || controller.isSaving }
  private var selectedTagCount: Int { draft.tagIDs.count + draft.newTagNames.count }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 6) {
        TextField("Add a task…", text: $draft.text, axis: .vertical)
          .font(.system(size: 15))
          .textFieldStyle(.roundedBorder)
          .lineLimit(1...2)
          .focused($textFocused)
          .onSubmit(submit)
          .disabled(isBusy)
          .accessibilityLabel("New task text")
          .accessibilityIdentifier("localTaskTextField")
        if isBusy { ProgressView().controlSize(.mini).padding(.top, 6) }
        Button("Add", action: submit)
          .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
          .disabled(isBusy || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .keyboardShortcut("s", modifiers: .command)
          .accessibilityIdentifier("saveLocalTaskButton")
        Button {
          presentation.finishDraft(id: draft.creationID)
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(PulseActionButtonStyle())
        .disabled(isBusy)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Cancel new task")
        .accessibilityIdentifier("cancelLocalTaskEditButton")
      }
      HStack(spacing: 6) {
        tagsMenu
          .frame(maxWidth: 100)
        TextField("New tag", text: $draft.newTagText)
          .font(.system(size: 12))
          .textFieldStyle(.roundedBorder)
          .onSubmit(addTag)
          .accessibilityIdentifier("localTaskNewTagField")
        Button(action: addTag) {
          Image(systemName: "plus")
        }
        .buttonStyle(PulseActionButtonStyle())
        .disabled(draft.newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("Add new tag")
        .accessibilityIdentifier("addDraftTagButton")
      }
      .disabled(isBusy)
      if let message = controller.errorMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("localTaskEditorError")
      }
    }
    .controlSize(.small)
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .accessibilityIdentifier("localTaskInlineComposer")
    .onAppear { textFocused = true }
  }

  private var tagsMenu: some View {
    Menu {
      let tags = controller.document?.tags ?? []
      if tags.isEmpty && draft.newTagNames.isEmpty {
        Text("No tags yet")
      }
      ForEach(tags) { tag in
        Toggle(
          tag.name,
          isOn: Binding(
            get: { draft.tagIDs.contains(tag.id) },
            set: { selected in
              if selected { draft.tagIDs.insert(tag.id) } else { draft.tagIDs.remove(tag.id) }
            })
        )
        .accessibilityIdentifier("localTaskTagChoice.\(tag.id.uuidString)")
      }
      if !tags.isEmpty && !draft.newTagNames.isEmpty { Divider() }
      ForEach(draft.newTagNames, id: \.self) { name in
        Button("Remove new tag: \(name)") { draft.newTagNames.removeAll(where: { $0 == name }) }
      }
    } label: {
      Label(selectedTagCount == 0 ? "Tags" : "Tags (\(selectedTagCount))", systemImage: "tag")
        .font(.system(size: 12))
        .lineLimit(1)
    }
    .accessibilityLabel("Choose task tags")
    .accessibilityIdentifier("localTaskTagsMenu")
  }

  private func addTag() {
    draft.acceptPendingTag(availableTags: controller.document?.tags ?? [])
  }

  private func submit() {
    guard !isBusy,
      !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    addTag()
    let snapshot = draft
    isSubmitting = true
    Task {
      defer { isSubmitting = false }
      if await controller.saveTask(
        id: nil, text: snapshot.text, tagIDs: snapshot.tagIDs,
        newTagNames: snapshot.newTagNames, creationID: snapshot.creationID)
      {
        let task = controller.document?.tasks.first(where: { $0.id == snapshot.creationID })
        presentation.didCreate(id: snapshot.creationID, task: task)
      }
    }
  }
}

@MainActor
struct LocalTaskRow: View {
  let task: LocalTask
  let isPending: Bool
  var isEditingEnabled = true
  let onToggle: () -> Void
  let onEdit: () -> Void

  @State private var isHovered = false

  var body: some View {
    HStack(alignment: .top, spacing: 2) {
      Button(action: onToggle) {
        Group {
          if isPending {
            ProgressView().controlSize(.mini)
          } else {
            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
              .font(.system(size: 15, weight: .medium))
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(Color(nsColor: .secondaryLabelColor))
          }
        }
        .padding(.top, 2)
        .frame(width: 28, height: 30, alignment: .top)
        .contentShape(Rectangle())
      }
      .buttonStyle(LocalTaskRowButtonStyle(isHovered: isHovered))
      .disabled(isPending)
      .help(task.completed ? "Mark incomplete" : "Mark complete")
      .accessibilityLabel("\(task.completed ? "Mark incomplete" : "Mark complete"): \(task.text)")
      .accessibilityValue(isPending ? "Saving" : (task.completed ? "Completed" : "Not completed"))
      .accessibilityIdentifier("localTaskCheckbox.\(task.id.uuidString)")

      Button(action: onEdit) {
        Text(task.text)
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(
            task.completed ? Color(nsColor: .secondaryLabelColor).opacity(0.7) : Color.primary
          )
          .strikethrough(task.completed, color: Color(nsColor: .tertiaryLabelColor))
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
          .contentShape(Rectangle())
      }
      .buttonStyle(LocalTaskRowButtonStyle(isHovered: isHovered))
      .disabled(!isEditingEnabled)
      .help(
        isEditingEnabled ? "Edit task" : "Add or cancel the new task before editing another task"
      )
      .accessibilityLabel(
        isEditingEnabled
          ? "Edit task: \(task.text)"
          : "\(task.text). Add or cancel the new task before editing"
      )
      .accessibilityIdentifier("localTaskText.\(task.id.uuidString)")
    }
    .onHover { isHovered = $0 }
  }
}

private struct LocalTaskFilterButton: View {
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
        .background(
          isSelected
            ? Color(nsColor: .selectedControlColor).opacity(0.16)
            : (isHovered ? Color(nsColor: .controlBackgroundColor) : .clear),
          in: Capsule()
        )
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
    .onHover { isHovered = $0 }
  }
}

private struct LocalTaskRowButtonStyle: ButtonStyle {
  let isHovered: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 2)
      .padding(.vertical, 3)
      .background(
        (isHovered || configuration.isPressed)
          ? Color(nsColor: .quaternaryLabelColor).opacity(configuration.isPressed ? 0.28 : 0.16)
          : .clear,
        in: RoundedRectangle(cornerRadius: 6)
      )
      .opacity(configuration.isPressed ? 0.72 : 1)
      .animation(.easeOut(duration: 0.12), value: isHovered)
  }
}

@MainActor
private struct LocalTaskEditor: View {
  @ObservedObject var controller: LocalTaskController
  @Binding var draft: LocalTaskDraft
  let onClose: () -> Void

  @FocusState private var textFocused: Bool
  @State private var isSubmitting = false

  private var isBusy: Bool { isSubmitting || controller.isSaving }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(draft.taskID == nil ? "New task" : "Edit task")
          .font(.system(size: 14, weight: .semibold))
        Spacer()
        Button("Cancel", action: onClose)
          .disabled(isBusy)
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("cancelLocalTaskEditButton")
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          Text("Task")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
          TextEditor(text: $draft.text)
            .font(.system(size: 15))
            .frame(minHeight: 64, maxHeight: 96)
            .padding(4)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            .focused($textFocused)
            .accessibilityLabel("Task text")
            .accessibilityIdentifier("localTaskTextField")

          Text("Tags")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
          ForEach(controller.document?.tags ?? []) { tag in
            Toggle(
              tag.name,
              isOn: Binding(
                get: { draft.tagIDs.contains(tag.id) },
                set: { selected in
                  if selected { draft.tagIDs.insert(tag.id) } else { draft.tagIDs.remove(tag.id) }
                }
              )
            )
            .toggleStyle(.checkbox)
            .font(.system(size: 13))
            .accessibilityIdentifier("localTaskTagChoice.\(tag.id.uuidString)")
          }
          ForEach(draft.newTagNames, id: \.self) { name in
            HStack(spacing: 6) {
              Image(systemName: "tag")
                .foregroundStyle(.secondary)
              Text(name)
                .font(.system(size: 13))
              Spacer()
              Button {
                draft.newTagNames.removeAll(where: { $0 == name })
              } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Remove new tag: \(name)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
              Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
          }
          HStack(spacing: 8) {
            TextField("New tag", text: $draft.newTagText)
              .textFieldStyle(.roundedBorder)
              .font(.system(size: 13))
              .onSubmit(addDraftTag)
              .accessibilityIdentifier("localTaskNewTagField")
            Button("Add", action: addDraftTag)
              .disabled(draft.newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              .accessibilityIdentifier("addDraftTagButton")
          }
          .buttonStyle(.borderless)
          if let errorMessage = controller.errorMessage {
            Text(errorMessage)
              .font(.caption)
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("localTaskEditorError")
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .disabled(isBusy)

      Divider()
      footer
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    .onAppear { textFocused = true }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      if draft.confirmsDeletion {
        Text("Delete this task? This cannot be undone.")
          .font(.caption)
          .fixedSize(horizontal: false, vertical: true)
        HStack {
          Button("Keep task") { draft.confirmsDeletion = false }
          Spacer()
          if isBusy { ProgressView().controlSize(.mini) }
          Button("Delete task", role: .destructive) {
            guard !isBusy else { return }
            guard let taskID = draft.taskID else { return }
            isSubmitting = true
            Task {
              defer { isSubmitting = false }
              if await controller.deleteTask(id: taskID) { onClose() }
            }
          }
          .accessibilityIdentifier("confirmDeleteLocalTaskButton")
        }
        .disabled(isBusy)
      } else {
        HStack {
          if draft.taskID != nil {
            Button("Delete", role: .destructive) { draft.confirmsDeletion = true }
              .disabled(isBusy)
              .accessibilityIdentifier("deleteLocalTaskButton")
          }
          Spacer()
          if isBusy {
            ProgressView().controlSize(.mini)
          }
          Button("Save") {
            guard !isBusy else { return }
            if !draft.newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              addDraftTag()
              guard draft.newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
              }
            }
            let snapshot = draft
            isSubmitting = true
            Task {
              defer { isSubmitting = false }
              if await controller.saveTask(
                id: snapshot.taskID,
                text: snapshot.text,
                tagIDs: snapshot.tagIDs,
                newTagNames: snapshot.newTagNames,
                creationID: snapshot.creationID
              ) {
                onClose()
              }
            }
          }
          .disabled(
            isBusy
              || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
          .keyboardShortcut("s", modifiers: .command)
          .accessibilityIdentifier("saveLocalTaskButton")
        }
      }
    }
    .buttonStyle(.borderless)
    .font(.system(size: 13, weight: .medium))
  }

  private func addDraftTag() {
    draft.acceptPendingTag(availableTags: controller.document?.tags ?? [])
  }
}
