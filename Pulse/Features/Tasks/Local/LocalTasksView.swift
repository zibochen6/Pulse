import AppKit
import SwiftUI

struct LocalTaskDraft: Equatable {
  var creationID = UUID()
  var taskID: UUID?
  var text = ""
  var selectedTagID: UUID?
  var repeatsDaily = false
  var newTagNames: [String] = []
  var newTagText = ""
  var optionsExpanded = false

  var tagIDs: Set<UUID> {
    get { selectedTagID.map { [$0] } ?? [] }
    set { selectedTagID = newValue.first }
  }
  var isDirty: Bool {
    !text.isEmpty || repeatsDaily || !newTagText.isEmpty || !newTagNames.isEmpty
  }
  init(taskID: UUID? = nil, text: String = "", tagIDs: Set<UUID> = [], repeatsDaily: Bool = false) {
    self.taskID = taskID
    self.text = text
    selectedTagID = tagIDs.first
    self.repeatsDaily = repeatsDaily
  }
  mutating func choose(_ id: UUID?) {
    selectedTagID = id
    newTagNames = []
    newTagText = ""
  }
  mutating func acceptPendingTag(availableTags: [TaskTag]) {
    let name = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    let canonical = LocalTaskStore.canonicalName(name)
    if canonical == "todo" {
      choose(nil)
    } else if let tag = availableTags.first(where: {
      LocalTaskStore.canonicalName($0.name) == canonical
    }) {
      choose(tag.id)
    } else {
      selectedTagID = nil
      newTagNames = [name]
      newTagText = ""
    }
  }
}

struct LocalTagIntent: Equatable {
  enum Action: Equatable {
    case create
    case rename(UUID)
    case delete(UUID)
  }
  let id = UUID()
  var action: Action = .create
  var name = ""
}

struct LocalTaskSubmission {
  let origin: LocalTaskFilter
  let draft: LocalTaskDraft
  let selectionRevision: Int
}

/// Lives above page navigation and popover closure. Each list has its own
/// creation intent; editing and tag management cannot replace those drafts.
@MainActor
final class LocalTaskPresentation: ObservableObject {
  @Published var selectedFilter: LocalTaskFilter = .untagged {
    didSet {
      guard oldValue != selectedFilter else { return }
      selectionRevision += 1
      ensureQuickDraft()
    }
  }
  @Published var quickDrafts: [LocalTaskFilter: LocalTaskDraft] = [.untagged: LocalTaskDraft()]
  @Published var editDraft: LocalTaskDraft?
  @Published var tagIntent: LocalTagIntent?
  @Published var composerFocused = false
  @Published var focusRequest = UUID()
  @Published var revealedTaskID: UUID?
  @Published var revealRequest = UUID()
  @Published var submittingIDs = Set<UUID>()
  @Published var collapsedCompleted = Set<LocalTaskFilter>()
  private var selectionRevision = 0

  var selectedTagID: UUID? {
    if case .tag(let id) = selectedFilter { return id }
    return nil
  }
  var quickDraft: LocalTaskDraft {
    get { quickDrafts[selectedFilter] ?? LocalTaskDraft(tagIDs: selectedTagID.map { [$0] } ?? []) }
    set { quickDrafts[selectedFilter] = newValue }
  }
  var isEditing: Bool {
    editDraft != nil || tagIntent != nil || composerFocused || quickDraft.isDirty
      || submittingIDs.contains(quickDraft.creationID)
  }
  func ensureQuickDraft() {
    if quickDrafts[selectedFilter] == nil {
      quickDrafts[selectedFilter] = LocalTaskDraft(tagIDs: selectedTagID.map { [$0] } ?? [])
    }
  }
  func beginAddingTask() {
    ensureQuickDraft()
    focusRequest = UUID()
  }
  func beginCreatingTag() {
    guard tagIntent == nil else { return }
    tagIntent = LocalTagIntent()
  }
  func beginEditingTask(_ task: LocalTask) {
    guard editDraft == nil else { return }
    editDraft = LocalTaskDraft(
      taskID: task.id, text: task.text, tagIDs: task.tagIDs, repeatsDaily: task.repeatsDaily)
    composerFocused = false
  }
  func finishDraft(id: UUID) {
    if editDraft?.creationID == id {
      editDraft = nil
    } else if quickDraft.creationID == id {
      quickDraft = LocalTaskDraft(tagIDs: selectedTagID.map { [$0] } ?? [])
    }
  }
  func captureEditSubmission() -> LocalTaskDraft? {
    guard let snapshot = editDraft, !submittingIDs.contains(snapshot.creationID) else { return nil }
    submittingIDs.insert(snapshot.creationID)
    return snapshot
  }
  func finishEditSubmission(
    _ snapshot: LocalTaskDraft, saved: Bool, task: LocalTask?, tags: [TaskTag]
  ) {
    submittingIDs.remove(snapshot.creationID)
    guard saved else { return }
    guard editDraft == snapshot else {
      if editDraft?.creationID == snapshot.creationID,
        let name = editDraft?.newTagNames.first,
        let existing = tags.first(where: {
          LocalTaskStore.canonicalName($0.name) == LocalTaskStore.canonicalName(name)
        })
      {
        editDraft?.selectedTagID = existing.id
        editDraft?.newTagNames = []
      }
      return
    }
    if let task { reveal(task, tags: tags) }
    editDraft = nil
  }
  func captureTagSubmission() -> LocalTagIntent? {
    guard let snapshot = tagIntent, !submittingIDs.contains(snapshot.id) else { return nil }
    submittingIDs.insert(snapshot.id)
    return snapshot
  }
  func finishTagSubmission(_ snapshot: LocalTagIntent, saved: Bool) {
    submittingIDs.remove(snapshot.id)
    guard saved, let current = tagIntent, current.id == snapshot.id else { return }
    guard current == snapshot else {
      if snapshot.action == .create {
        tagIntent = LocalTagIntent(action: current.action, name: current.name)
      }
      return
    }
    tagIntent = nil
    if snapshot.action == .create {
      selectedFilter = .tag(snapshot.id)
      beginAddingTask()
    }
  }
  func captureSubmission() -> LocalTaskSubmission? {
    ensureQuickDraft()
    let current = quickDraft
    guard !submittingIDs.contains(current.creationID),
      !current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    submittingIDs.insert(current.creationID)
    return LocalTaskSubmission(
      origin: selectedFilter, draft: current, selectionRevision: selectionRevision)
  }
  func finishSubmission(
    _ submission: LocalTaskSubmission, saved: Bool, task: LocalTask?, tags: [TaskTag]
  ) {
    submittingIDs.remove(submission.draft.creationID)
    guard saved else { return }
    let unchanged = quickDrafts[submission.origin] == submission.draft
    guard unchanged else {
      // This ID has been consumed on disk; retain later input as a fresh
      // creation instead of trapping its next save behind taskConflict.
      if quickDrafts[submission.origin]?.creationID == submission.draft.creationID {
        quickDrafts[submission.origin]?.creationID = UUID()
        if let name = quickDrafts[submission.origin]?.newTagNames.first,
          let existing = tags.first(where: {
            LocalTaskStore.canonicalName($0.name) == LocalTaskStore.canonicalName(name)
          })
        {
          quickDrafts[submission.origin]?.selectedTagID = existing.id
          quickDrafts[submission.origin]?.newTagNames = []
        }
      }
      return
    }
    let originID: UUID? = {
      if case .tag(let id) = submission.origin { return id }
      return nil
    }()
    quickDrafts[submission.origin] = LocalTaskDraft(tagIDs: originID.map { [$0] } ?? [])
    if selectedFilter == submission.origin, selectionRevision == submission.selectionRevision {
      if let task { reveal(task, tags: tags) }
      focusRequest = UUID()
    }
  }
  func reveal(_ task: LocalTask, tags: [TaskTag]) {
    selectedFilter =
      tags.first(where: { task.tagIDs.contains($0.id) }).map { .tag($0.id) } ?? .untagged
    if task.completed { collapsedCompleted.remove(selectedFilter) }
    revealedTaskID = task.id
    revealRequest = UUID()
  }
  func reconcileTags(_ tags: [TaskTag]) {
    let available = Set(tags.map(\.id))
    if let selectedTagID, !available.contains(selectedTagID) { selectedFilter = .untagged }
    if selectedFilter == .all { selectedFilter = .untagged }
    // Reconcile destinations without replacing any retained creation intent.
    for key in Array(quickDrafts.keys) {
      if let id = quickDrafts[key]?.selectedTagID, !available.contains(id) {
        quickDrafts[key]?.selectedTagID = nil
      }
    }
    if let id = editDraft?.selectedTagID, !available.contains(id) { editDraft?.selectedTagID = nil }
    ensureQuickDraft()
  }
}

@MainActor
struct LocalTasksView: View {
  @ObservedObject var controller: LocalTaskController
  @ObservedObject var presentation: LocalTaskPresentation
  let onEditingChanged: (Bool) -> Void

  var body: some View {
    Group {
      if let draft = presentation.editDraft {
        LocalTaskEditor(
          controller: controller, presentation: presentation,
          draft: Binding(
            get: { presentation.editDraft ?? draft }, set: { presentation.editDraft = $0 }))
      } else {
        taskList
      }
    }
    .onAppear {
      presentation.reconcileTags(controller.document?.tags ?? [])
      onEditingChanged(presentation.isEditing)
    }
    .task {
      if controller.document == nil { await controller.refresh() }
      await controller.resetRepeatingTasks()
    }
    .onChange(of: presentation.isEditing) { onEditingChanged($0) }
    .onDisappear {
      presentation.composerFocused = false
      onEditingChanged(false)
    }
    .onChange(of: controller.document?.tags) {
      if let tags = $0 { presentation.reconcileTags(tags) }
    }
  }

  private var taskList: some View {
    VStack(spacing: 0) {
      if let document = controller.document {
        tagBar(document.tags)
        Divider()
        if presentation.tagIntent != nil {
          LocalTagEntry(controller: controller, presentation: presentation)
          Divider()
        }
        LocalTaskQuickComposer(controller: controller, presentation: presentation)
        Divider()
      }
      errorBanner
      if controller.document != nil {
        taskScrollView
      } else if controller.isLoading {
        ProgressView("Loading tasks").font(.caption).frame(
          maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Text("Tasks could not be loaded. Your saved file has not been cleared.")
          .font(.caption).foregroundStyle(.secondary)
          .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      if let receipt = controller.deletionHistory.last {
        Divider()
        HStack(spacing: 8) {
          Text("Deleted task").font(.caption).foregroundStyle(.secondary)
          Spacer()
          if controller.isUndoing { ProgressView().controlSize(.mini) }
          Button("Undo") {
            Task {
              if await controller.undoDeletion(),
                let restored = controller.document?.tasks.first(where: { $0.id == receipt.task.id })
              {
                presentation.reveal(restored, tags: controller.document?.tags ?? [])
              }
            }
          }
          .buttonStyle(PulseActionButtonStyle())
          .disabled(controller.isSaving || controller.isUndoing)
          .help("Restore the last deleted task (\(controller.deletionHistory.count) available)")
          .accessibilityIdentifier("undoLocalTaskDeletionButton")
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
      }
    }
  }

  private var taskScrollView: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          let filter = presentation.selectedFilter
          let incomplete = controller.incompleteTasks(matching: filter)
          let completed = controller.completedTasks(matching: filter)
          if incomplete.isEmpty && completed.isEmpty {
            Text(filter == .untagged ? "No tasks yet" : "No tasks in this tag")
              .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 12)
          }
          ForEach(incomplete) { taskRow($0).id($0.id) }
          if !completed.isEmpty {
            Button {
              if presentation.collapsedCompleted.contains(filter) {
                presentation.collapsedCompleted.remove(filter)
              } else {
                presentation.collapsedCompleted.insert(filter)
              }
            } label: {
              HStack(spacing: 5) {
                Image(
                  systemName: presentation.collapsedCompleted.contains(filter)
                    ? "chevron.right" : "chevron.down")
                Text("Completed (\(completed.count))")
                Spacer()
              }
              .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
              .padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("completedTasksHeading")
            .accessibilityValue(
              presentation.collapsedCompleted.contains(filter) ? "Collapsed" : "Expanded")
            if !presentation.collapsedCompleted.contains(filter) {
              ForEach(completed) { taskRow($0).id($0.id) }
            }
          }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityIdentifier("localTaskList")
      .onAppear { scrollToRevealedTask(using: proxy) }
      .onChange(of: presentation.revealRequest) { _ in scrollToRevealedTask(using: proxy) }
    }
  }

  private func scrollToRevealedTask(using proxy: ScrollViewProxy) {
    guard let id = presentation.revealedTaskID else { return }
    let request = presentation.revealRequest
    // Editor saves replace the editor with a new reader. Wait for its rows to
    // mount, then consume this request exactly once across appearance/change.
    DispatchQueue.main.async {
      guard presentation.editDraft == nil,
        presentation.revealRequest == request, presentation.revealedTaskID == id
      else { return }
      proxy.scrollTo(id, anchor: .center)
      presentation.revealedTaskID = nil
    }
  }

  private func taskRow(_ task: LocalTask) -> some View {
    LocalTaskRow(
      task: task, isPending: controller.pendingTaskIDs.contains(task.id),
      onToggle: { controller.setCompleted(!task.completed, taskID: task.id) },
      onEdit: { presentation.beginEditingTask(task) },
      onDelete: { Task { _ = await controller.deleteTask(id: task.id) } })
  }

  private func tagBar(_ tags: [TaskTag]) -> some View {
    HStack(spacing: 2) {
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 4) {
            PulsePillTab(
              title: "Todo", isSelected: presentation.selectedFilter == .untagged,
              action: { presentation.selectedFilter = .untagged }
            )
            .id(LocalTaskFilter.untagged).accessibilityIdentifier("localTaskFilter.todo")
            ForEach(tags) { tag in
              PulsePillTab(
                title: tag.name, isSelected: presentation.selectedFilter == .tag(tag.id),
                action: { presentation.selectedFilter = .tag(tag.id) }
              )
              .id(LocalTaskFilter.tag(tag.id))
              .accessibilityIdentifier("localTaskFilter.\(tag.id.uuidString)")
              .contextMenu {
                Button("Rename…") {
                  presentation.tagIntent = LocalTagIntent(action: .rename(tag.id), name: tag.name)
                }
                Button("Remove tag…", role: .destructive) {
                  presentation.tagIntent = LocalTagIntent(action: .delete(tag.id), name: tag.name)
                }
              }
            }
          }
          .padding(.leading, 14).padding(.vertical, 3)
        }
        .onAppear { proxy.scrollTo(presentation.selectedFilter, anchor: .center) }
        .onChange(of: presentation.selectedFilter) { proxy.scrollTo($0, anchor: .center) }
        .onChange(of: tags.map(\.id)) { _ in
          proxy.scrollTo(presentation.selectedFilter, anchor: .center)
        }
      }
      Button {
        presentation.beginCreatingTag()
      } label: {
        Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(
          width: 28, height: 28)
      }
      .buttonStyle(PulseIconButtonStyle()).help("New tag")
      .accessibilityLabel("New tag").accessibilityIdentifier("addLocalTagButton")
      .padding(.trailing, 10)
    }
  }

  @ViewBuilder private var errorBanner: some View {
    if let failure = controller.completionFailures.values.sorted(by: {
      $0.taskID.uuidString < $1.taskID.uuidString
    }).first {
      PulseErrorBanner(message: failure.message, accessibilityIdentifier: "localTaskError") {
        Button("Try again") { controller.retryCompletion(failure) }
        Button("Dismiss") { controller.dismissCompletionFailure(taskID: failure.taskID) }
      }
    }
    if let message = controller.errorMessage {
      PulseErrorBanner(message: message, accessibilityIdentifier: "localTaskSaveError") {
        Button("Reload") { Task { await controller.refresh() } }.disabled(controller.isLoading)
        Button("Dismiss") { controller.dismissError() }
      }
    }
  }
}

@MainActor
private struct LocalTagEntry: View {
  @ObservedObject var controller: LocalTaskController
  @ObservedObject var presentation: LocalTaskPresentation
  @State private var focusRequest = UUID()
  private var isSubmitting: Bool { presentation.submittingIDs.contains(intent.id) }

  private var intent: LocalTagIntent { presentation.tagIntent ?? LocalTagIntent() }
  private var existing: TaskTag? {
    controller.document?.tags.first {
      LocalTaskStore.canonicalName($0.name) == LocalTaskStore.canonicalName(intent.name)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if case .delete = intent.action {
        Text("Remove “\(intent.name)”? Its tasks will move to Todo.").font(.caption)
        HStack {
          Button("Keep tag") { presentation.tagIntent = nil }
          Spacer()
          Button("Remove tag", role: .destructive, action: submit)
            .accessibilityIdentifier("confirmDeleteLocalTagButton")
        }
      } else {
        HStack(spacing: 6) {
          TaskEntryField(
            text: Binding(get: { intent.name }, set: { presentation.tagIntent?.name = $0 }),
            placeholder: "Tag name", identifier: "newLocalTagNameField", focusRequest: focusRequest,
            isEnabled: !isSubmitting, onSubmit: submit, onFocusChanged: { _ in }
          )
          .frame(height: 24)
          Button(intent.action == .create ? "Create" : "Save", action: submit)
            .disabled(intent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("saveLocalTagButton")
          Button {
            presentation.tagIntent = nil
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("Cancel tag").accessibilityIdentifier("cancelLocalTagButton")
        }
        if intent.action == .create, let existing {
          HStack {
            Text("This tag already exists.").font(.caption).foregroundStyle(.secondary)
            Button("Use \(existing.name)") { useTag(existing.id) }
          }
        } else if LocalTaskStore.canonicalName(intent.name) == "todo" {
          Button("Use Todo") { useTag(nil) }
        }
      }
      if isSubmitting { ProgressView().controlSize(.mini) }
    }
    .buttonStyle(PulseActionButtonStyle()).font(.system(size: 12))
    .padding(.horizontal, 14).padding(.vertical, 8).disabled(isSubmitting)
    .accessibilityIdentifier("localTagEntry")
    .onAppear { focusRequest = UUID() }
  }
  private func useTag(_ id: UUID?) {
    presentation.selectedFilter = id.map { .tag($0) } ?? .untagged
    presentation.tagIntent = nil
    presentation.beginAddingTask()
    controller.dismissError()
  }
  private func submit() {
    guard !isSubmitting else { return }
    if intent.action == .create, existing != nil { return }
    guard let snapshot = presentation.captureTagSubmission() else { return }
    Task {
      let saved: Bool
      switch snapshot.action {
      case .create: saved = await controller.createTag(id: snapshot.id, name: snapshot.name)
      case .rename(let id): saved = await controller.renameTag(id: id, name: snapshot.name)
      case .delete(let id): saved = await controller.deleteTag(id: id)
      }
      presentation.finishTagSubmission(snapshot, saved: saved)
    }
  }
}

@MainActor
private struct LocalTaskQuickComposer: View {
  @ObservedObject var controller: LocalTaskController
  @ObservedObject var presentation: LocalTaskPresentation
  private var draft: Binding<LocalTaskDraft> {
    Binding(get: { presentation.quickDraft }, set: { presentation.quickDraft = $0 })
  }
  private var isBusy: Bool {
    presentation.submittingIDs.contains(presentation.quickDraft.creationID)
  }
  private var listName: String {
    presentation.quickDraft.newTagNames.first
      ?? controller.document?.tags.first(where: { $0.id == presentation.quickDraft.selectedTagID })?
      .name ?? "Todo"
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        TaskEntryField(
          text: draft.text, placeholder: "Add to \(listName)…", identifier: "localTaskTextField",
          focusRequest: presentation.focusRequest, isEnabled: !isBusy, onSubmit: submit,
          onFocusChanged: { presentation.composerFocused = $0 }
        )
        .frame(height: 26)
        if isBusy { ProgressView().controlSize(.mini) }
        Button(action: submit) { Image(systemName: "arrow.up").frame(width: 22, height: 24) }
          .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
          .disabled(
            isBusy
              || presentation.quickDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
          )
          .help("Add task (Return)").accessibilityLabel("Add task").accessibilityIdentifier(
            "saveLocalTaskButton")
        Button {
          presentation.quickDraft.optionsExpanded.toggle()
        } label: {
          Image(systemName: "slider.horizontal.3").frame(width: 22, height: 24)
        }
        .buttonStyle(PulseIconButtonStyle()).disabled(isBusy).help("Task options")
        .accessibilityLabel("Task options").accessibilityIdentifier("localTaskOptionsButton")
      }
      if presentation.quickDraft.optionsExpanded {
        LocalTaskOptions(
          controller: controller, draft: draft,
          onFocusChanged: { presentation.composerFocused = $0 }
        )
        .disabled(isBusy)
      }
    }
    .padding(.horizontal, 14).padding(.vertical, 9)
    .accessibilityIdentifier("localTaskInlineComposer")
  }
  private func submit() {
    guard !isBusy else { return }
    presentation.quickDraft.acceptPendingTag(availableTags: controller.document?.tags ?? [])
    guard let submission = presentation.captureSubmission() else { return }
    Task {
      let snapshot = submission.draft
      let saved = await controller.saveTask(
        id: nil, text: snapshot.text, tagIDs: snapshot.tagIDs,
        newTagNames: snapshot.newTagNames, repeatsDaily: snapshot.repeatsDaily,
        creationID: snapshot.creationID)
      let task = controller.document?.tasks.first { $0.id == snapshot.creationID }
      presentation.finishSubmission(
        submission, saved: saved, task: task, tags: controller.document?.tags ?? [])
    }
  }
}

@MainActor
private struct LocalTaskOptions: View {
  @ObservedObject var controller: LocalTaskController
  @Binding var draft: LocalTaskDraft
  var onFocusChanged: (Bool) -> Void = { _ in }
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        Menu {
          Button {
            draft.choose(nil)
          } label: {
            if draft.selectedTagID == nil && draft.newTagNames.isEmpty {
              Label("Todo", systemImage: "checkmark")
            } else {
              Text("Todo")
            }
          }
          ForEach(controller.document?.tags ?? []) { tag in
            Button {
              draft.choose(tag.id)
            } label: {
              if draft.selectedTagID == tag.id {
                Label(tag.name, systemImage: "checkmark")
              } else {
                Text(tag.name)
              }
            }
          }
        } label: {
          Label(
            draft.newTagNames.first ?? controller.document?.tags.first(where: {
              $0.id == draft.selectedTagID
            })?.name ?? "Todo", systemImage: "tag"
          )
          .lineLimit(1)
        }
        .accessibilityLabel("Choose task list").accessibilityIdentifier("localTaskTagsMenu")
        Spacer(minLength: 0)
        Toggle("Repeat daily", isOn: $draft.repeatsDaily)
          .toggleStyle(.checkbox).fixedSize().accessibilityIdentifier("localTaskRepeatsDailyToggle")
      }
      HStack(spacing: 6) {
        // Native field bridge also prevents an IME confirmation from staging a tag.
        TaskEntryField(
          text: $draft.newTagText, placeholder: "New tag", identifier: "localTaskNewTagField",
          focusRequest: nil, isEnabled: true, onSubmit: addTag, onFocusChanged: onFocusChanged
        )
        .frame(height: 24)
        Button("Use tag", action: addTag)
          .buttonStyle(PulseActionButtonStyle())
          .disabled(draft.newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityIdentifier("addDraftTagButton")
      }
      if let newName = draft.newTagNames.first {
        Text("New list: \(newName)").foregroundStyle(.secondary).lineLimit(2)
      }
    }
    .font(.system(size: 12)).controlSize(.small)
  }
  private func addTag() { draft.acceptPendingTag(availableTags: controller.document?.tags ?? []) }
}

@MainActor
private struct LocalTaskEditor: View {
  @ObservedObject var controller: LocalTaskController
  @ObservedObject var presentation: LocalTaskPresentation
  @Binding var draft: LocalTaskDraft
  private var isSubmitting: Bool { presentation.submittingIDs.contains(draft.creationID) }
  @FocusState private var textFocused: Bool
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Edit task").font(.system(size: 14, weight: .semibold))
        Spacer()
        Button("Cancel") { presentation.editDraft = nil }
          .keyboardShortcut(.cancelAction).accessibilityIdentifier("cancelLocalTaskEditButton")
      }
      .buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 10)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          Text("Task").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
          TextEditor(text: $draft.text).font(.system(size: 15))
            .frame(minHeight: 80, maxHeight: 120).padding(4)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            .focused($textFocused).accessibilityLabel("Task text").accessibilityIdentifier(
              "localTaskTextField")
          DisclosureGroup("Task options", isExpanded: $draft.optionsExpanded) {
            LocalTaskOptions(controller: controller, draft: $draft).padding(.top, 6)
          }.font(.system(size: 12))
          if let error = controller.errorMessage {
            Text(error).font(.caption).foregroundStyle(.red).fixedSize(
              horizontal: false, vertical: true)
          }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
      }
      Divider()
      HStack {
        Button("Delete", role: .destructive) {
          guard !isSubmitting, let id = draft.taskID else { return }
          guard let snapshot = presentation.captureEditSubmission() else { return }
          Task {
            let saved = await controller.deleteTask(id: id)
            presentation.finishEditSubmission(
              snapshot, saved: saved, task: nil, tags: controller.document?.tags ?? [])
          }
        }.accessibilityIdentifier("deleteLocalTaskButton")
        Spacer()
        if isSubmitting { ProgressView().controlSize(.mini) }
        Button("Save", action: save)
          .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .keyboardShortcut("s", modifiers: .command).accessibilityIdentifier("saveLocalTaskButton")
      }
      .buttonStyle(PulseActionButtonStyle()).font(.system(size: 13))
      .padding(.horizontal, 16).padding(.vertical, 10)
    }
    .disabled(isSubmitting).onAppear { textFocused = true }
  }
  private func save() {
    guard !isSubmitting else { return }
    draft.acceptPendingTag(availableTags: controller.document?.tags ?? [])
    guard let snapshot = presentation.captureEditSubmission() else { return }
    Task {
      let saved = await controller.saveTask(
        id: snapshot.taskID, text: snapshot.text, tagIDs: snapshot.tagIDs,
        newTagNames: snapshot.newTagNames, repeatsDaily: snapshot.repeatsDaily,
        creationID: snapshot.creationID)
      let task = controller.document?.tasks.first(where: { $0.id == snapshot.taskID })
      presentation.finishEditSubmission(
        snapshot, saved: saved, task: task, tags: controller.document?.tags ?? [])
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
  var onDelete: (() -> Void)?
  @State private var isHovered = false
  private enum Control: Hashable { case complete, edit, delete }
  @FocusState private var focusedControl: Control?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(alignment: .top, spacing: 2) {
      Button(action: onToggle) {
        Group {
          if isPending {
            ProgressView().controlSize(.mini)
          } else {
            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
              .font(.system(size: 15, weight: .medium)).symbolRenderingMode(.hierarchical)
              .foregroundStyle(
                task.completed ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
          }
        }
        .padding(.top, 2).frame(width: 28, height: 30, alignment: .top).contentShape(Rectangle())
      }
      .buttonStyle(PulseRowButtonStyle(isHovered: isHovered)).disabled(isPending)
      .focused($focusedControl, equals: .complete)
      .help(task.completed ? "Mark incomplete" : "Mark complete")
      .accessibilityLabel("\(task.completed ? "Mark incomplete" : "Mark complete"): \(task.text)")
      .accessibilityValue(isPending ? "Saving" : (task.completed ? "Completed" : "Not completed"))
      .accessibilityIdentifier("localTaskCheckbox.\(task.id.uuidString)")
      Button(action: onEdit) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(task.text).font(.system(size: 15))
            .foregroundStyle(
              task.completed ? Color(nsColor: .secondaryLabelColor).opacity(0.7) : Color.primary
            )
            .strikethrough(task.completed, color: Color(nsColor: .tertiaryLabelColor))
            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
          if task.repeatsDaily {
            Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.tertiary).accessibilityHidden(true)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading).contentShape(Rectangle())
      }
      .buttonStyle(PulseRowButtonStyle(isHovered: isHovered)).disabled(
        !isEditingEnabled || isPending
      )
      .focused($focusedControl, equals: .edit)
      .help("Edit task").accessibilityLabel("Edit task: \(task.text)")
      .accessibilityValue(task.repeatsDaily ? "Repeats daily" : "")
      .accessibilityIdentifier("localTaskText.\(task.id.uuidString)")
      if let onDelete {
        Button(action: onDelete) {
          Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
        }
        .buttonStyle(PulseIconButtonStyle()).disabled(isPending)
        .focused($focusedControl, equals: .delete)
        .opacity(isHovered || focusedControl != nil ? 1 : 0)
        .help("Delete task").accessibilityLabel("Delete task: \(task.text)")
        .accessibilityIdentifier("deleteLocalTaskRowButton.\(task.id.uuidString)")
      }
    }
    .onHover { isHovered = $0 }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    .contextMenu {
      Button("Edit task", action: onEdit).disabled(isPending)
      if let onDelete {
        Button("Delete task", role: .destructive, action: onDelete).disabled(isPending)
      }
    }
    .onDeleteCommand { if focusedControl != nil, !isPending { onDelete?() } }
  }
}

/// NSTextField delegates receive commands after the input manager has had its
/// chance to confirm marked text. Never interpret a marked-text Return as save.
@MainActor
struct TaskEntryField: NSViewRepresentable {
  @Environment(\.isEnabled) private var environmentEnabled
  @Binding var text: String
  let placeholder: String
  let identifier: String
  let focusRequest: UUID?
  var isEnabled = true
  let onSubmit: () -> Void
  let onFocusChanged: (Bool) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> FocusableTaskTextField {
    let field = FocusableTaskTextField()
    field.delegate = context.coordinator
    field.font = .systemFont(ofSize: identifier == "localTaskTextField" ? 15 : 13)
    field.isBezeled = true
    field.bezelStyle = .roundedBezel
    field.focusRingType = .none
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.setAccessibilityIdentifier(identifier)
    field.setAccessibilityLabel(placeholder)
    return field
  }
  func updateNSView(_ field: FocusableTaskTextField, context: Context) {
    context.coordinator.parent = self
    if field.stringValue != text { field.stringValue = text }
    field.placeholderString = placeholder
    field.setAccessibilityLabel(placeholder)
    field.isEnabled = isEnabled && environmentEnabled
    if context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      field.needsRequestedFocus = focusRequest != nil
      field.applyRequestedFocus()
    }
  }
  static func dismantleNSView(_ field: FocusableTaskTextField, coordinator: Coordinator) {
    coordinator.stopObservingEditorUndo()
    field.delegate = nil
  }
  @MainActor
  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: TaskEntryField
    var lastFocusRequest: UUID?
    private weak var activeEditor: NSTextView?
    init(_ parent: TaskEntryField) {
      self.parent = parent
      lastFocusRequest = parent.focusRequest
    }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      parent.text = field.stringValue
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
      stopObservingEditorUndo()
      if let editor = (notification.object as? NSTextField)?.currentEditor() as? NSTextView,
        let manager = editor.undoManager
      {
        activeEditor = editor
        NotificationCenter.default.addObserver(
          self, selector: #selector(editorUndoDidChange(_:)),
          name: .NSUndoManagerDidUndoChange, object: manager)
        NotificationCenter.default.addObserver(
          self, selector: #selector(editorUndoDidChange(_:)),
          name: .NSUndoManagerDidRedoChange, object: manager)
      }
      parent.onFocusChanged(true)
    }
    func controlTextDidEndEditing(_ notification: Notification) {
      if let field = notification.object as? NSTextField { parent.text = field.stringValue }
      stopObservingEditorUndo()
      parent.onFocusChanged(false)
    }
    // AppKit's shared field editor does not send controlTextDidChange when
    // undo/redo changes its string. Sync that native edit before a SwiftUI
    // update can put the stale binding back into the field.
    @objc private func editorUndoDidChange(_ notification: Notification) {
      if let activeEditor { parent.text = activeEditor.string }
    }
    func stopObservingEditorUndo() {
      NotificationCenter.default.removeObserver(
        self, name: .NSUndoManagerDidUndoChange, object: nil)
      NotificationCenter.default.removeObserver(
        self, name: .NSUndoManagerDidRedoChange, object: nil)
      activeEditor = nil
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
      -> Bool
    {
      guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
      guard !textView.hasMarkedText() else { return false }
      parent.onSubmit()
      return true
    }
  }
}

@MainActor
final class FocusableTaskTextField: NSTextField {
  var needsRequestedFocus = false
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyRequestedFocus()
  }
  func applyRequestedFocus() {
    guard needsRequestedFocus, let window else { return }
    needsRequestedFocus = false
    // AppKit responder changes may invoke delegates. Defer beyond SwiftUI's
    // update pass so focus reporting never publishes from updateNSView.
    DispatchQueue.main.async { [weak self, weak window] in
      guard let self, self.window === window else { return }
      window?.makeFirstResponder(self)
    }
  }
}
