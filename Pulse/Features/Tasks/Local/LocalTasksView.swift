import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LocalTaskDraft: Equatable {
  var creationID = UUID()
  var taskID: UUID?
  var text = ""
  var selectedTagID: UUID?
  var repeatsDaily = false
  var newTagNames: [String] = []
  var newTagText = ""
  var optionsExpanded = false
  var newTagInputVisible = false

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
    newTagInputVisible = false
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
      newTagInputVisible = false
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
  let expansionRevision: Int
}

/// Lives above page navigation and popover closure. Each list has its own
/// creation intent; editing and tag management cannot replace those drafts.
@MainActor
final class LocalTaskPresentation: ObservableObject {
  @Published var selectedFilter: LocalTaskFilter = .untagged {
    didSet {
      guard oldValue != selectedFilter else { return }
      selectionRevision += 1
      composerFocused = false
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
  @Published var expandedComposers = Set<LocalTaskFilter>()
  private var expansionRevisions: [LocalTaskFilter: Int] = [:]
  private var selectionRevision = 0

  /// Tag drag state. `draggingTagID` also suspends pointer-departure dismissal,
  /// so a drag that runs to the popover's edge is not cut short mid-move.
  @Published var draggingTagID: UUID?
  @Published var tagDropTarget: LocalTagDropTarget?
  /// Optimistic order for a tag move that has not been confirmed yet. It only
  /// previews the drop; the store's order still decides drafts, selection and
  /// undo, and replaces this as soon as the write lands.
  @Published var pendingTagOrder: [UUID]?
  /// Measured pill centres of the tag bar. They live here rather than in view
  /// state so the drop coordinator can read them live instead of freezing a
  /// layout snapshot at the moment the drag started.
  @Published var tagBarGeometry = TagBarGeometry()

  var selectedTagID: UUID? {
    if case .tag(let id) = selectedFilter { return id }
    return nil
  }
  var quickDraft: LocalTaskDraft {
    get { quickDrafts[selectedFilter] ?? LocalTaskDraft(tagIDs: selectedTagID.map { [$0] } ?? []) }
    set { quickDrafts[selectedFilter] = newValue }
  }
  var isComposerExpanded: Bool { expandedComposers.contains(selectedFilter) }
  var isEditing: Bool {
    editDraft != nil || tagIntent != nil
      || (isComposerExpanded && (composerFocused || quickDraft.isDirty))
      || submittingIDs.contains(quickDraft.creationID)
  }
  /// Editing and an engaged tag drop both hold the popover open. Only an
  /// *engaged* drop counts, never a bare drag: `dropExited` and `performDrop`
  /// both clear `tagDropTarget`, so a drag cancelled with Escape can never
  /// leave the popover pinned open by a flag nothing resets.
  var isInteractionActive: Bool {
    isEditing || tagDropTarget != nil
  }
  func ensureQuickDraft() {
    if quickDrafts[selectedFilter] == nil {
      quickDrafts[selectedFilter] = LocalTaskDraft(tagIDs: selectedTagID.map { [$0] } ?? [])
    }
  }
  func beginAddingTask() {
    ensureQuickDraft()
    expandedComposers.insert(selectedFilter)
    expansionRevisions[selectedFilter, default: 0] += 1
    focusRequest = UUID()
  }
  func collapseComposer() {
    expandedComposers.remove(selectedFilter)
    expansionRevisions[selectedFilter, default: 0] += 1
    composerFocused = false
  }
  func beginCreatingTag() {
    guard tagIntent == nil else { return }
    tagIntent = LocalTagIntent()
  }

  // MARK: - Tag drag and reorder

  func beginTagDrag(_ id: UUID) {
    draggingTagID = id
    tagDropTarget = nil
  }

  func updateTagDrop(_ target: LocalTagDropTarget?) {
    tagDropTarget = target
  }

  func endTagDrag() {
    draggingTagID = nil
    tagDropTarget = nil
  }

  /// Publishes the drop immediately and returns the store's `toIndex`.
  /// `nil` means the drop changed nothing and must not be persisted.
  func commitTagMove(_ id: UUID, to target: LocalTagDropTarget?, tagIDs: [UUID]) -> Int? {
    guard draggingTagID == id, let target else {
      endTagDrag()
      return nil
    }
    return commitTagMove(id, toIndex: target.index, tagIDs: tagIDs)
  }

  /// The same optimistic publish for the keyboard and context-menu path, which
  /// has no caret geometry to hand over. Returns the store's `toIndex`, or
  /// `nil` when the requested slot is the tag's current one.
  func commitTagMove(_ id: UUID, toIndex: Int, tagIDs: [UUID]) -> Int? {
    defer { endTagDrag() }
    guard tagIDs.contains(id), toIndex >= 0, toIndex < tagIDs.count,
      toIndex != tagIDs.firstIndex(of: id)
    else { return nil }
    var order = tagIDs
    order.removeAll { $0 == id }
    order.insert(id, at: toIndex)
    pendingTagOrder = order
    return toIndex
  }

  /// The store's order replaces the preview once it matches it, so a confirmed
  /// move is visually silent instead of animating twice.
  func reconcileTagOrder(_ tags: [TaskTag]) {
    if pendingTagOrder == tags.map(\.id) { pendingTagOrder = nil }
  }

  /// A move that never reached storage drops its preview rather than leaving
  /// an order the file does not have.
  func abandonTagMove() {
    pendingTagOrder = nil
    endTagDrag()
  }

  /// The order the tag bar renders: the preview while a move is pending, the
  /// stored order otherwise. A tag created during a pending move is appended so
  /// a stale preview can never hide it.
  func displayOrder(_ tags: [TaskTag]) -> [TaskTag] {
    guard let order = pendingTagOrder else { return tags }
    let byID = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    return order.compactMap { byID[$0] } + tags.filter { !order.contains($0.id) }
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
      origin: selectedFilter, draft: current, selectionRevision: selectionRevision,
      expansionRevision: expansionRevisions[selectedFilter, default: 0])
  }
  func finishSubmission(
    _ submission: LocalTaskSubmission, saved: Bool, task: LocalTask?, tags: [TaskTag]
  ) {
    submittingIDs.remove(submission.draft.creationID)
    guard saved else { return }
    let unchanged =
      quickDrafts[submission.origin] == submission.draft
      && expansionRevisions[submission.origin, default: 0] == submission.expansionRevision
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
    expandedComposers.remove(submission.origin)
    if selectedFilter == submission.origin, selectionRevision == submission.selectionRevision {
      composerFocused = false
      if let task { reveal(task, tags: tags) }
    }
  }
  func reveal(_ task: LocalTask, tags: [TaskTag]) {
    selectedFilter =
      tags.first(where: { task.tagIDs.contains($0.id) }).map { .tag($0.id) } ?? .untagged
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
  @State private var dropCoordinator = TagBarDropCoordinator()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The tag bar's selection plate. With a namespace, the accent capsule is a
  /// single view that slides between pills; without one the pill falls back to
  /// a static fill, which is what Reduce Motion gets anyway.
  @Namespace private var tagPlate

  /// Rows arrive from the top and leave the same way, so switching lists reads
  /// as content moving rather than as a list being torn down and rebuilt.
  private var rowTransition: AnyTransition {
    .opacity.combined(with: .move(edge: .top))
  }

  /// `nil` under Reduce Motion: the plate then lands in place instead of
  /// sliding, while every other part of selection feedback stays identical.
  private var selectionPlateNamespace: Namespace.ID? {
    reduceMotion ? nil : tagPlate
  }

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
      presentation.reconcileTagOrder(controller.document?.tags ?? [])
      onEditingChanged(presentation.isInteractionActive)
    }
    .task {
      if controller.document == nil { await controller.refresh() }
      await controller.resetRepeatingTasks()
    }
    .onChange(of: presentation.isInteractionActive) { onEditingChanged($0) }
    .onDisappear {
      presentation.composerFocused = false
      presentation.endTagDrag()
      onEditingChanged(false)
    }
    .onChange(of: controller.document?.tags) {
      if let tags = $0 {
        presentation.reconcileTags(tags)
        presentation.reconcileTagOrder(tags)
      }
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
      }
      errorBanner
        .animation(
          reduceMotion ? nil : PulseDesignTokens.insertionAnimation,
          value: controller.errorMessage != nil || !controller.completionFailures.isEmpty)
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
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(
      reduceMotion ? nil : PulseDesignTokens.insertionAnimation,
      value: controller.deletionHistory.last?.id)
  }

  /// The ids in display order. Used as the animation key for the list surface:
  /// a task that is added or deleted is inserted or removed with the list's
  /// row transition, while a completion changes no id at all — the task stays
  /// exactly where it was and only strikes through in place.
  private var taskIDs: [UUID] {
    controller.tasks(matching: presentation.selectedFilter).map(\.id)
  }

  private var taskScrollView: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          let filter = presentation.selectedFilter
          let tasks = controller.tasks(matching: filter)
          if tasks.isEmpty {
            Text(filter == .untagged ? "No tasks yet" : "No tasks in this tag")
              .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 12)
          }
          ForEach(tasks) { task in
            taskRow(task).id(task.id).transition(rowTransition)
          }
          if presentation.isComposerExpanded {
            LocalTaskQuickComposer(controller: controller, presentation: presentation)
              .id(presentation.selectedFilter)
              // Asymmetric on purpose. The insertion may glide in, but the
              // removal must be immediate: the composer owns a shared AppKit
              // field editor, and lingering in the tree through a removal
              // transition is exactly how a saved draft gets typed back into a
              // field that should already be gone.
              .transition(
                .asymmetric(
                  insertion: .opacity.combined(with: .move(edge: .bottom)),
                  removal: .identity))
          } else {
            addTaskEntry
          }
          Color.clear.frame(height: 1).id("taskComposerEnd")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Three values, three curves: rows change with the list, the composer
        // grows from its entry point, and a finished task acknowledges in
        // place. All are set before the view ever mounts in the rendering
        // tests, so none can capture a mid-flight value in an off-window
        // render.
        .animation(
          reduceMotion ? nil : PulseDesignTokens.tabSwitchAnimation,
          value: presentation.selectedFilter)
        .animation(
          reduceMotion ? nil : PulseDesignTokens.composerAnimation,
          value: presentation.isComposerExpanded)
        // Membership of the list itself. A completion leaves every id in
        // place, so finishing a task never animates the row anywhere — and a
        // background refresh that only touches a timestamp animates nothing
        // either.
        .animation(reduceMotion ? nil : PulseDesignTokens.completionAnimation, value: taskIDs)
      }
      .accessibilityIdentifier("localTaskList")
      .onAppear {
        scrollToRevealedTask(using: proxy)
        if presentation.isComposerExpanded { scrollToComposer(using: proxy) }
      }
      .onChange(of: presentation.focusRequest) { _ in scrollToComposer(using: proxy) }
      .onChange(of: presentation.selectedFilter) { _ in
        if presentation.isComposerExpanded { scrollToComposer(using: proxy) }
      }
      .onChange(of: presentation.quickDraft.optionsExpanded) { _ in
        scrollToComposer(using: proxy)
      }
      .onChange(of: presentation.quickDraft.newTagInputVisible) { _ in
        scrollToComposer(using: proxy)
      }
      .onChange(of: presentation.revealRequest) { _ in scrollToRevealedTask(using: proxy) }
    }
  }

  /// The list's closing entry point. Text-first and left-aligned so it reads as
  /// an invitation in the list rather than as a floating icon parked in the
  /// middle of an otherwise empty column.
  private var addTaskEntry: some View {
    Button {
      presentation.beginAddingTask()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "plus")
          .font(.system(size: PulseDesignTokens.caption, weight: .semibold))
        Text("Add task")
          .font(.system(size: PulseDesignTokens.footnote, weight: .medium))
      }
      .foregroundStyle(.secondary)
    }
    .buttonStyle(PulseFooterActionStyle())
    .help("Add task")
    .accessibilityLabel("Add task")
    .accessibilityIdentifier("addLocalTaskButton")
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 4)
    .transition(.opacity.combined(with: .move(edge: .top)))
  }

  private func scrollToComposer(using proxy: ScrollViewProxy) {
    let origin = presentation.selectedFilter
    let request = presentation.focusRequest
    DispatchQueue.main.async {
      guard presentation.isComposerExpanded, presentation.selectedFilter == origin,
        presentation.focusRequest == request, presentation.editDraft == nil
      else { return }
      proxy.scrollTo("taskComposerEnd", anchor: .bottom)
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
    let displayed = presentation.displayOrder(tags)
    let tagIDs = displayed.map(\.id)
    return HStack(spacing: 2) {
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 4) {
            PulsePillTab(
              title: "Todo", isSelected: presentation.selectedFilter == .untagged,
              action: { presentation.selectedFilter = .untagged },
              plateNamespace: selectionPlateNamespace
            )
            .id(LocalTaskFilter.untagged).accessibilityIdentifier("localTaskFilter.todo")
            .background(tagMidpointReporter { TagBarGeometry(todoMidX: $0) })
            ForEach(displayed) { tag in
              tagPill(tag, tagIDs: tagIDs)
            }
          }
          .padding(.leading, 14).padding(.vertical, 3)
          .coordinateSpace(name: TagBarGeometry.spaceName)
          .onPreferenceChange(TagBarGeometryKey.self) { presentation.tagBarGeometry = $0 }
          .onDrop(of: [.text], delegate: dropCoordinator)
          // Scoped to the tag row: this is what makes the selection plate
          // travel between pills instead of vanishing from one and appearing in
          // another. The list below keeps its own curve.
          .animation(
            reduceMotion ? nil : PulseDesignTokens.tabSwitchAnimation,
            value: presentation.selectedFilter)
        }
        .onAppear { proxy.scrollTo(presentation.selectedFilter, anchor: .center) }
        .onChange(of: presentation.selectedFilter) { selection in
          withAnimation(reduceMotion ? nil : PulseDesignTokens.tabSwitchAnimation) {
            proxy.scrollTo(selection, anchor: .center)
          }
        }
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
      .accessibilityLabel("New tag")
      .accessibilityHint("Creates a new list next to Todo")
      .accessibilityIdentifier("addLocalTagButton")
      .padding(.trailing, 10)
    }
    .onAppear { configureDropCoordinator() }
  }

  /// One custom tag pill: selectable, draggable and a drop target, with the
  /// insertion caret drawn on the edge the tag would leave through.
  private func tagPill(_ tag: TaskTag, tagIDs: [UUID]) -> some View {
    let isDragging = presentation.draggingTagID == tag.id
    let dropEdge =
      presentation.tagDropTarget?.pillID == tag.id ? presentation.tagDropTarget?.edge : nil
    return PulsePillTab(
      title: tag.name, isSelected: presentation.selectedFilter == .tag(tag.id),
      action: { presentation.selectedFilter = .tag(tag.id) },
      plateNamespace: selectionPlateNamespace
    )
    .id(LocalTaskFilter.tag(tag.id))
    .accessibilityIdentifier("localTaskFilter.\(tag.id.uuidString)")
    .contextMenu {
      let index = tagIDs.firstIndex(of: tag.id)
      Button("Move Left") { moveTag(tag, in: tagIDs, to: (index ?? 0) - 1) }
        .disabled(index == nil || index == 0)
        .keyboardShortcut(.leftArrow, modifiers: [.option, .command])
      Button("Move Right") { moveTag(tag, in: tagIDs, to: (index ?? 0) + 1) }
        .disabled(index == nil || index == tagIDs.count - 1)
        .keyboardShortcut(.rightArrow, modifiers: [.option, .command])
      Divider()
      Button("Rename…") {
        presentation.tagIntent = LocalTagIntent(action: .rename(tag.id), name: tag.name)
      }
      Button("Remove tag…", role: .destructive) {
        presentation.tagIntent = LocalTagIntent(action: .delete(tag.id), name: tag.name)
      }
    }
    .onDrag {
      presentation.beginTagDrag(tag.id)
      return NSItemProvider(object: tag.id.uuidString as NSString)
    }
    .overlay(alignment: .leading) {
      if dropEdge == .leading {
        tagDropCaret.offset(x: -1)
      }
    }
    .overlay(alignment: .trailing) {
      if dropEdge == .trailing {
        tagDropCaret.offset(x: 1)
      }
    }
    .background(tagMidpointReporter { TagBarGeometry(tagMidXByID: [tag.id: $0]) })
    .opacity(isDragging ? 0.45 : 1)
    .scaleEffect(isDragging ? 0.96 : 1)
    .accessibilityHint("Drag to reorder")
    .accessibilityAction(named: Text("Move left")) { moveTag(tag, in: tagIDs, to: (tagIDs.firstIndex(of: tag.id) ?? 0) - 1) }
    .accessibilityAction(named: Text("Move right")) {
      moveTag(tag, in: tagIDs, to: (tagIDs.firstIndex(of: tag.id) ?? 0) + 1)
    }
  }

  private var tagDropCaret: some View {
    Capsule()
      .fill(Color.accentColor)
      .frame(width: 2, height: 18)
      .allowsHitTesting(false)
  }

  /// Reports this pill's centre into the bar's named coordinate space. The
  /// report comes from a background geometry reader, so an animated offset
  /// drawn on top of a pill can never feed back into the drop hit test.
  private func tagMidpointReporter(_ build: @escaping (CGFloat) -> TagBarGeometry) -> some View {
    GeometryReader { proxy in
      Color.clear.preference(
        key: TagBarGeometryKey.self,
        value: build(proxy.frame(in: .named(TagBarGeometry.spaceName)).midX))
    }
  }

  /// The coordinator is created once and its closures capture the two reference
  /// types only, so they stay valid across body re-evaluations and SwiftUI
  /// never has to replace a `DropDelegate` in the middle of a drag.
  private func configureDropCoordinator() {
    let presentation = presentation
    let controller = controller
    dropCoordinator.onLocation = { location in
      presentation.updateTagDrop(
        tagDropTarget(
          draggedID: presentation.draggingTagID, locationX: location.x,
          tags: controller.document?.tags ?? [], geometry: presentation.tagBarGeometry))
    }
    dropCoordinator.onCommit = { location in
      let tags = controller.document?.tags ?? []
      guard let draggedID = presentation.draggingTagID else {
        presentation.endTagDrag()
        return
      }
      let target = tagDropTarget(
        draggedID: draggedID, locationX: location.x, tags: tags,
        geometry: presentation.tagBarGeometry)
      guard let toIndex = presentation.commitTagMove(draggedID, to: target, tagIDs: tags.map(\.id))
      else { return }
      Task {
        let saved = await controller.moveTag(id: draggedID, toIndex: toIndex)
        if !saved { presentation.abandonTagMove() }
      }
    }
    dropCoordinator.onExit = { presentation.updateTagDrop(nil) }
  }

  /// Keyboard and context-menu reorder: the same optimistic publish as a drop,
  /// without any caret geometry.
  private func moveTag(_ tag: TaskTag, in tagIDs: [UUID], to index: Int) {
    let clamped = max(0, min(index, tagIDs.count - 1))
    guard let toIndex = presentation.commitTagMove(tag.id, toIndex: clamped, tagIDs: tagIDs)
    else { return }
    Task {
      let saved = await controller.moveTag(id: tag.id, toIndex: toIndex)
      if !saved { presentation.abandonTagMove() }
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
    let origin = presentation.selectedFilter
    let creationID = presentation.quickDraft.creationID
    return Binding(
      get: { presentation.quickDrafts[origin] ?? LocalTaskDraft() },
      set: {
        guard presentation.quickDrafts[origin]?.creationID == creationID else { return }
        presentation.quickDrafts[origin] = $0
      })
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
          onFocusChanged: { presentation.composerFocused = $0 },
          onCancel: { presentation.collapseComposer() }
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
        Button {
          presentation.collapseComposer()
        } label: {
          Image(systemName: "xmark").font(.system(size: 11)).frame(width: 24, height: 26)
        }
        .buttonStyle(PulseIconButtonStyle()).help("Collapse input (Esc)")
        .accessibilityLabel("Collapse input").accessibilityIdentifier("collapseLocalTaskButton")
      }
      if presentation.quickDraft.optionsExpanded {
        LocalTaskOptions(
          controller: controller, draft: draft,
          onFocusChanged: { presentation.composerFocused = $0 },
          onCancel: { presentation.collapseComposer() }
        )
        .disabled(isBusy)
      }
    }
    .padding(.vertical, 9)
    .accessibilityIdentifier("localTaskInlineComposer")
    .onExitCommand { presentation.collapseComposer() }
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
  var onCancel: (() -> Void)?
  @State private var tagFocusRequest: UUID?

  private var listName: String {
    draft.newTagNames.first ?? controller.document?.tags.first(where: {
      $0.id == draft.selectedTagID
    })?.name ?? "Todo"
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Text("List").foregroundStyle(.secondary)
        Spacer(minLength: 12)
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
          Divider()
          Button("New tag…") {
            draft.newTagInputVisible = true
            tagFocusRequest = UUID()
          }
          .accessibilityIdentifier("newDraftTagButton")
        } label: {
          Text(listName).lineLimit(1).truncationMode(.middle)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Choose task list").accessibilityIdentifier("localTaskTagsMenu")
      }
      if draft.newTagInputVisible {
        HStack(spacing: 6) {
          TaskEntryField(
            text: Binding(
              get: { draft.newTagText },
              set: {
                // The shared field editor may finish after this conditional
                // field disappears. Do not reinsert the name just accepted.
                if draft.newTagInputVisible { draft.newTagText = $0 }
              }),
            placeholder: "New tag", identifier: "localTaskNewTagField",
            focusRequest: tagFocusRequest, isEnabled: true, onSubmit: addTag,
            onFocusChanged: onFocusChanged, onCancel: onCancel
          )
          .frame(height: 26)
          Button("Use tag", action: addTag)
            .buttonStyle(PulseActionButtonStyle())
            .disabled(draft.newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("addDraftTagButton")
        }
      }
      HStack {
        Text("Repeat daily").foregroundStyle(.secondary)
        Spacer()
        Toggle("Repeat daily", isOn: $draft.repeatsDaily)
          .labelsHidden().toggleStyle(.switch).controlSize(.mini)
          .accessibilityIdentifier("localTaskRepeatsDailyToggle")
      }
    }
    .font(.system(size: 13)).controlSize(.small)
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
        Button("Cancel") { presentation.editDraft = nil }
          .keyboardShortcut(.cancelAction).accessibilityIdentifier("cancelLocalTaskEditButton")
          .frame(width: 60, alignment: .leading)
        Spacer(minLength: 0)
        Text("Edit task").font(.system(size: 14, weight: .semibold))
        Spacer(minLength: 0)
        HStack(spacing: 4) {
          if isSubmitting { ProgressView().controlSize(.mini) }
          Button("Save", action: save)
            .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut("s", modifiers: .command)
            .accessibilityIdentifier("saveLocalTaskButton")
        }
        .frame(width: 60, alignment: .trailing)
      }
      .buttonStyle(.borderless).font(.system(size: 13))
      .padding(.horizontal, 16).padding(.vertical, 12)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          TextEditor(text: $draft.text).font(.system(size: 15))
            .scrollContentBackground(.hidden)
            .frame(height: 148).padding(10)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .focused($textFocused).accessibilityLabel("Task text")
            .accessibilityIdentifier("localTaskTextField")
          LocalTaskOptions(controller: controller, draft: $draft)
          if let error = controller.errorMessage {
            Text(error).font(.caption).foregroundStyle(.red).fixedSize(
              horizontal: false, vertical: true)
          }
          Button("Delete task", role: .destructive, action: delete)
            .buttonStyle(.borderless).font(.system(size: 12))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("deleteLocalTaskButton")
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .disabled(isSubmitting).onAppear { textFocused = true }
  }
  private func delete() {
    guard !isSubmitting, let id = draft.taskID else { return }
    guard let snapshot = presentation.captureEditSubmission() else { return }
    Task {
      let saved = await controller.deleteTask(id: id)
      presentation.finishEditSubmission(
        snapshot, saved: saved, task: nil, tags: controller.document?.tags ?? [])
    }
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
        // One structure, never a swap. The pending spinner used to *replace*
        // the check control, which rebuilt the button mid-save and dropped the
        // completion animation that was about to run. Now the circle and check
        // stay mounted, the spinner only covers them while the write is in
        // flight, and nothing about the button's identity changes.
        ZStack {
          ZStack {
            Image(systemName: "circle")
              .font(.system(size: 15, weight: .medium)).symbolRenderingMode(.hierarchical)
              .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            // The check pops in instead of swapping glyphs, which is what
            // makes a completion feel acknowledged rather than merely
            // updated. Both symbols stay mounted so the static appearance is
            // unchanged; only the transition differs.
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 15, weight: .medium)).symbolRenderingMode(.hierarchical)
              .foregroundStyle(Color.accentColor)
              .scaleEffect(task.completed ? 1 : 0.4)
              .opacity(task.completed ? 1 : 0)
          }
          .animation(
            reduceMotion ? nil : PulseDesignTokens.selectionAnimation, value: task.completed)
          .opacity(isPending ? 0 : 1)
          if isPending {
            ProgressView().controlSize(.mini).transition(.opacity)
          }
        }
        .padding(.top, 2).frame(width: 28, height: 30, alignment: .top).contentShape(Rectangle())
      }
      .buttonStyle(PulseRowButtonStyle(isHovered: isHovered)).disabled(isPending)
      .animation(
        reduceMotion ? nil : PulseDesignTokens.completionAnimation, value: isPending)
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
        .scaleEffect(isHovered || focusedControl != nil ? 1 : 0.8)
        .help("Delete task").accessibilityLabel("Delete task: \(task.text)")
        .accessibilityIdentifier("deleteLocalTaskRowButton.\(task.id.uuidString)")
      }
    }
    .onHover { isHovered = $0 }
    .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
    .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: focusedControl)
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
  var onCancel: (() -> Void)?

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
      lastFocusRequest = nil
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
      guard !textView.hasMarkedText() else { return false }
      if commandSelector == #selector(NSResponder.cancelOperation(_:)), let cancel = parent.onCancel
      {
        cancel()
        return true
      }
      guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
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

// MARK: - Tag bar drop geometry

/// Pill centres of the tag bar, measured in the bar's own named coordinate
/// space. The drop hit test reads them, so they must come from layout rather
/// than from any animated offset drawn on top of the pills.
struct TagBarGeometry: Equatable, Sendable {
  static let spaceName = "pulseTagBar"
  var todoMidX: CGFloat?
  var tagMidXByID: [UUID: CGFloat] = [:]
}

struct TagBarGeometryKey: PreferenceKey {
  static let defaultValue = TagBarGeometry()

  static func reduce(value: inout TagBarGeometry, nextValue: () -> TagBarGeometry) {
    let next = nextValue()
    if let todoMidX = next.todoMidX { value.todoMidX = todoMidX }
    value.tagMidXByID.merge(next.tagMidXByID, uniquingKeysWith: { $1 })
  }
}

/// Resolves where a drop at `locationX` would land, or `nil` while the bar is
/// still unmeasured or the drag is not one of our own tags.
private func tagDropTarget(
  draggedID: UUID?, locationX: CGFloat, tags: [TaskTag], geometry: TagBarGeometry
) -> LocalTagDropTarget? {
  guard let draggedID, let todoMidX = geometry.todoMidX else { return nil }
  return LocalTagReorder.dropTarget(
    draggedID: draggedID, locationX: locationX, tagIDs: tags.map(\.id), todoMidX: todoMidX,
    midXByID: geometry.tagMidXByID)
}

/// Bridges SwiftUI's drag session to the tag bar's reorder state.
///
/// `DropDelegate.dropUpdated` is the only place SwiftUI reports a drag's live
/// position, which is what keeps the insertion caret under the pointer instead
/// of answering only at the moment of release.
@MainActor
final class TagBarDropCoordinator: DropDelegate {
  var onLocation: (CGPoint) -> Void = { _ in }
  var onCommit: (CGPoint) -> Void = { _ in }
  var onExit: () -> Void = {}

  func validateDrop(info: DropInfo) -> Bool {
    !info.itemProviders(for: [.text]).isEmpty
  }

  func dropEntered(info: DropInfo) { onLocation(info.location) }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    onLocation(info.location)
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) { onExit() }

  func performDrop(info: DropInfo) -> Bool {
    onCommit(info.location)
    return true
  }
}
