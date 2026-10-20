import SwiftUI

/// Kept above page navigation so an accidental popover close does not discard a draft.
/// The tab selection is likewise presentation state: it never edits a stored task.
@MainActor
final class LocalTaskPresentation: ObservableObject {
  /// Tags are the only visible tabs. `All` never appears, and an empty vocabulary
  /// falls back to `.untagged` so new users can still add their first task.
  @Published var selectedFilter: LocalTaskFilter = .untagged
  @Published var draft: LocalTaskDraft?

  /// The tags in creation order, mirrored from the document. Selection has to
  /// follow that order rather than `Set` iteration, which would pick a
  /// different tab for the same multi-tag task on every launch.
  private var orderedTags: [TaskTag] = []

  var isEditing: Bool { draft != nil }

  /// The concrete tag currently shown, used to pre-fill new tasks and to place
  /// the tag bar's `+` menu.
  var selectedTagID: UUID? {
    if case .tag(let tagID) = selectedFilter { return tagID }
    return nil
  }

  func beginAddingTask() {
    draft = LocalTaskDraft(tagIDs: selectedTagID.map { [$0] } ?? [])
  }

  /// The tag bar's `+` adds a task in the tag the user picked, not necessarily
  /// the one on screen, so the new row is where the user expects it.
  func beginAddingTask(in tagID: UUID) {
    draft = LocalTaskDraft(tagIDs: [tagID])
  }

  /// The tag bar's "New tag…" intent. Leaving the shown tab first is what keeps
  /// the current tag off the draft, whose whole point is a brand-new one.
  func beginAddingTaskWithNewTag() {
    selectedFilter = .untagged
    beginAddingTask()
  }

  func beginEditingTask(_ task: LocalTask) {
    // Existing rows stay visible during inline creation; an incidental text
    // click must not replace that unsaved or pending creation intent.
    guard draft == nil else { return }
    draft = LocalTaskDraft(
      taskID: task.id, text: task.text, tagIDs: task.tagIDs, repeatsDaily: task.repeatsDaily)
  }

  func finishDraft(id: UUID) {
    guard draft?.creationID == id else { return }
    draft = nil
  }

  /// A confirmed task keeps the tab that already shows it; otherwise the tab
  /// moves so the user can see what they just created.
  ///
  /// `tags` is the document's current tags: a brand-new tag created by this
  /// same submission may not have reached `reconcileTags` yet, and revealing it
  /// is exactly when the new tag matters.
  func didCreate(id: UUID, task: LocalTask?, tags: [TaskTag]? = nil) {
    guard draft?.creationID == id else { return }
    if let task {
      if let tagID = selectedTagID {
        if !task.tagIDs.contains(tagID) {
          reveal(tagIDs: task.tagIDs, in: tags ?? orderedTags)
        }
      } else if !task.tagIDs.isEmpty {
        reveal(tagIDs: task.tagIDs, in: tags ?? orderedTags)
      }
    }
    draft = nil
  }

  /// The untagged filter exists only as the guidance state for an empty tag
  /// vocabulary; any saved tag makes the first tag the default tab.
  func reconcileTags(_ tags: [TaskTag]) {
    orderedTags = tags
    let availableIDs = Set(tags.map(\.id))
    if let selectedTagID {
      if !availableIDs.contains(selectedTagID) {
        selectedFilter = tags.first.map { LocalTaskFilter.tag($0.id) } ?? .untagged
      }
    } else if let first = tags.first {
      selectedFilter = .tag(first.id)
    }
    if var currentDraft = draft {
      let remainingIDs = currentDraft.tagIDs.intersection(availableIDs)
      if remainingIDs != currentDraft.tagIDs {
        currentDraft.tagIDs = remainingIDs
        draft = currentDraft
      }
    }
  }

  /// Reveals the earliest-created tag of the new task, so a multi-tag task
  /// always lands on the same tab instead of whichever ID hashes first.
  private func reveal(tagIDs: Set<UUID>, in tags: [TaskTag]) {
    selectedFilter =
      tags.first(where: { tagIDs.contains($0.id) }).map { LocalTaskFilter.tag($0.id) }
      ?? .untagged
  }
}

struct LocalTaskDraft {
  let creationID = UUID()
  var taskID: UUID?
  var text = ""
  var tagIDs: Set<UUID> = []
  var repeatsDaily = false
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

/// The Home task surface: tag tabs, the task list, and one inline composer that
/// is opened either by the centered `+` under the list or by the tag bar's `+`.
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
      // Popover opens are the reliable clock tick for repeating tasks: a task
      // finished yesterday returns unchecked the first time Pulse is opened.
      await controller.resetRepeatingTasks()
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
        tagBar(document.tags)
        Divider()
      }
      errorBanner

      if controller.document != nil {
        taskScrollView
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
    }
  }

  private var taskScrollView: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 2) {
        let filter = presentation.selectedFilter
        let incomplete = controller.incompleteTasks(matching: filter)
        let completed = controller.completedTasks(matching: filter)
        if incomplete.isEmpty && completed.isEmpty {
          Text(emptyMessage)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
        }
        ForEach(incomplete) { task in
          taskRow(task)
        }
        if !completed.isEmpty {
          if !incomplete.isEmpty {
            Text("Completed")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.tertiary)
              .padding(.top, 8)
              .padding(.bottom, 1)
              .accessibilityIdentifier("completedTasksHeading")
          }
          ForEach(completed) { task in
            taskRow(task)
          }
        }
        // The add affordance sits directly under the last row, where the eye
        // already is after reading the list, instead of pinned to the popover
        // bottom across a large empty area.
        footer
          .padding(.top, 6)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityIdentifier("localTaskList")
  }

  private var emptyMessage: String {
    controller.document?.tags.isEmpty == true ? "No tasks yet" : "No tasks in this tag"
  }

  /// A failed completion stays reachable even while a draft is open, because
  /// its retry is a different row's problem; ordinary save errors belong to the
  /// composer or editor that holds the draft, so the banner only appears when
  /// no draft is open.
  @ViewBuilder
  private var errorBanner: some View {
    let completionFailure =
      controller.document?.tasks.compactMap {
        controller.completionFailures[$0.id]
      }.first
      ?? controller.completionFailures.sorted {
        $0.key.uuidString < $1.key.uuidString
      }.first?.value
    if let completionFailure {
      // Retry replays the recorded intent, so a daily task keeps the day it was
      // clicked rather than being re-dated to the retry's day.
      errorContent(
        completionFailure.message,
        onRetry: { controller.retryCompletion(completionFailure) },
        onDismiss: {
          controller.dismissCompletionFailure(taskID: completionFailure.taskID)
        }
      )
      Divider()
    } else if let errorMessage = controller.errorMessage, presentation.draft == nil {
      errorContent(
        errorMessage,
        onRetry: { Task { await controller.refresh() } },
        onDismiss: { controller.dismissError() }
      )
      Divider()
    }
  }

  /// The centered `+` is the resting state; an active draft takes its place so
  /// the composer appears exactly where the user just clicked, under the list.
  @ViewBuilder
  private var footer: some View {
    if let draft = presentation.draft, draft.taskID == nil {
      LocalTaskInlineComposer(
        controller: controller, presentation: presentation,
        draft: Binding(
          get: { presentation.draft ?? draft }, set: { presentation.draft = $0 }))
    } else if presentation.draft == nil {
      Button {
        controller.dismissError()
        presentation.beginAddingTask()
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 13, weight: .semibold))
          .frame(width: 28, height: 28)
      }
      .buttonStyle(PulseIconButtonStyle())
      .help("Add task")
      .accessibilityLabel("Add task")
      .accessibilityIdentifier("addLocalTaskButton")
      .frame(maxWidth: .infinity)
    }
  }

  private func taskRow(_ task: LocalTask) -> some View {
    LocalTaskRow(
      task: task,
      isPending: controller.pendingTaskIDs.contains(task.id),
      isEditingEnabled: presentation.draft == nil,
      onToggle: { controller.setCompleted(!task.completed, taskID: task.id) },
      onEdit: { presentation.beginEditingTask(task) },
      onDelete: { Task { _ = await controller.deleteTask(id: task.id) } }
    )
  }

  /// Tabs are the saved tags in creation order. `All` and `Untagged` are not
  /// offered; an empty vocabulary is represented by a single guidance tab.
  private func tagBar(_ tags: [TaskTag]) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        if tags.isEmpty {
          PulsePillTab(
            title: "Todo",
            isSelected: true,
            action: {}
          )
          .accessibilityIdentifier("localTaskFilter.todo")
        }
        ForEach(tags) { tag in
          PulsePillTab(
            title: tag.name,
            isSelected: presentation.selectedFilter == .tag(tag.id),
            action: { presentation.selectedFilter = .tag(tag.id) }
          )
          .accessibilityIdentifier("localTaskFilter.\(tag.id.uuidString)")
        }
        tagMenu(tags)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 3)
    }
  }

  /// One menu for both "add to an existing tag" and "create a tag with a task".
  private func tagMenu(_ tags: [TaskTag]) -> some View {
    Menu {
      if !tags.isEmpty {
        Section("Add task in tag") {
          ForEach(tags) { tag in
            Button(tag.name) {
              controller.dismissError()
              presentation.beginAddingTask(in: tag.id)
            }
            .accessibilityIdentifier("addTaskInTag.\(tag.id.uuidString)")
          }
        }
      }
      Button {
        controller.dismissError()
        presentation.beginAddingTaskWithNewTag()
      } label: {
        Label("New tag…", systemImage: "tag")
      }
      .accessibilityIdentifier("addTaskWithNewTagButton")
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 26, height: 26)
        .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Add a task in a tag")
    .accessibilityLabel("Add a task in a tag")
    .accessibilityIdentifier("addTagTaskMenu")
  }

  private func errorContent(
    _ message: String, onRetry: @escaping () -> Void, onDismiss: @escaping () -> Void
  ) -> some View {
    PulseErrorBanner(
      message: message,
      accessibilityIdentifier: "localTaskError"
    ) {
      Button("Try again", action: onRetry)
        .disabled(controller.isSaving || controller.isLoading)
      Button("Dismiss", action: onDismiss)
    }
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
      RepeatDailyToggle(isOn: $draft.repeatsDaily)
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
        newTagNames: snapshot.newTagNames, repeatsDaily: snapshot.repeatsDaily,
        creationID: snapshot.creationID)
      {
        let task = controller.document?.tasks.first(where: { $0.id == snapshot.creationID })
        presentation.didCreate(
          id: snapshot.creationID, task: task, tags: controller.document?.tags)
      }
    }
  }
}

/// A completed task stays visible but dimmed and struck through, and can be
/// removed from its own row without opening the editor.
@MainActor
struct LocalTaskRow: View {
  let task: LocalTask
  let isPending: Bool
  var isEditingEnabled = true
  let onToggle: () -> Void
  let onEdit: () -> Void
  var onDelete: (() -> Void)?

  @State private var isHovered = false
  @State private var confirmsDeletion = false

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
              .foregroundStyle(
                task.completed ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
          }
        }
        .padding(.top, 2)
        .frame(width: 28, height: 30, alignment: .top)
        .contentShape(Rectangle())
      }
      .buttonStyle(PulseRowButtonStyle(isHovered: isHovered))
      .disabled(isPending)
      .help(task.completed ? "Mark incomplete" : "Mark complete")
      .accessibilityLabel("\(task.completed ? "Mark incomplete" : "Mark complete"): \(task.text)")
      .accessibilityValue(isPending ? "Saving" : (task.completed ? "Completed" : "Not completed"))
      .accessibilityIdentifier("localTaskCheckbox.\(task.id.uuidString)")

      Button(action: onEdit) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(task.text)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(
              task.completed
                ? Color(nsColor: .secondaryLabelColor).opacity(0.7) : Color.primary
            )
            .strikethrough(task.completed, color: Color(nsColor: .tertiaryLabelColor))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
          if task.repeatsDaily {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.tertiary)
              .padding(.top, 2)
              .accessibilityHidden(true)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
        .contentShape(Rectangle())
      }
      .buttonStyle(PulseRowButtonStyle(isHovered: isHovered))
      .disabled(!isEditingEnabled)
      .help(
        isEditingEnabled ? "Edit task" : "Add or cancel the new task before editing another task"
      )
      .accessibilityLabel(
        isEditingEnabled
          ? "Edit task: \(task.text)"
          : "\(task.text). Add or cancel the new task before editing"
      )
      .accessibilityValue(task.repeatsDaily ? "Repeats daily" : "")
      .accessibilityIdentifier("localTaskText.\(task.id.uuidString)")

      // Staying mounted while confirming matters: the dialog is attached to
      // this button, so dropping it on mouse-out would dismiss an open confirm.
      if let onDelete, (isHovered || confirmsDeletion), !isPending {
        Button {
          confirmsDeletion = true
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
        }
        .buttonStyle(PulseIconButtonStyle())
        .help("Delete task")
        .accessibilityLabel("Delete task: \(task.text)")
        .accessibilityIdentifier("deleteLocalTaskRowButton.\(task.id.uuidString)")
        .confirmationDialog(
          "Delete “\(task.text)”?",
          isPresented: $confirmsDeletion,
          titleVisibility: .visible
        ) {
          Button("Delete task", role: .destructive) { onDelete() }
            .accessibilityIdentifier("confirmDeleteLocalTaskButton")
          Button("Keep task", role: .cancel) {}
        } message: {
          Text("This cannot be undone.")
        }
        .transition(.opacity)
      }
    }
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovered)
  }
}

/// One switch shared by the inline composer and the full editor so the two
/// creation paths cannot drift apart.
private struct RepeatDailyToggle: View {
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) {
      HStack(spacing: 4) {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 10, weight: .semibold))
        Text("Repeat daily")
          .font(.system(size: 12))
      }
      .foregroundStyle(.secondary)
    }
    .toggleStyle(.checkbox)
    .help("Resets this task to unfinished each new day")
    .accessibilityIdentifier("localTaskRepeatsDailyToggle")
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

          RepeatDailyToggle(isOn: $draft.repeatsDaily)

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
                repeatsDaily: snapshot.repeatsDaily,
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
