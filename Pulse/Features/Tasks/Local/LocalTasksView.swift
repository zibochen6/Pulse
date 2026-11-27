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

  func conflictingTag(in tags: [TaskTag]) -> TaskTag? {
    tags.first { tag in
      if case .rename(let id) = action, id == tag.id { return false }
      return LocalTaskStore.canonicalName(tag.name) == LocalTaskStore.canonicalName(name)
    }
  }

  func hasValidName(in tags: [TaskTag]) -> Bool {
    let canonical = LocalTaskStore.canonicalName(name)
    return !canonical.isEmpty && canonical != "todo" && conflictingTag(in: tags) == nil
  }
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
      clearComposerFocus()
      ensureQuickDraft()
      composerActivation.configureField()
    }
  }
  @Published var quickDrafts: [LocalTaskFilter: LocalTaskDraft] = [.untagged: LocalTaskDraft()]
  @Published var editDraft: LocalTaskDraft?
  @Published var tagIntent: LocalTagIntent?
  @Published var tagSearch = ""
  @Published var composerFocused = false
  @Published var focusRequest = UUID()
  @Published private(set) var pendingComposerFocus: UUID?
  @Published var revealedTaskID: UUID?
  @Published var revealRequest = UUID()
  @Published var submittingIDs = Set<UUID>()
  @Published var expandedComposers = Set<LocalTaskFilter>()
  private var expansionRevisions: [LocalTaskFilter: Int] = [:]
  private var selectionRevision = 0
  let composerActivation = TaskEntryActivation()

  /// Only an actual native session holds dismissal; its guaranteed ended callback
  /// releases the hold even when a drag leaves the panel or Escape cancels it.
  @Published private(set) var nativeTagDragActive = false
  @Published var draggingTagID: UUID?
  @Published var tagDropTarget: LocalTagDropTarget?
  /// Optimistic order for a tag move that has not been confirmed yet. It only
  /// previews the drop; the store's order still decides drafts, selection and
  /// undo, and replaces this as soon as the write lands.
  @Published var pendingTagOrder: [UUID]?
  /// Event handlers read these latest measurements without invalidating the list.
  var tagBarGeometry = TagBarGeometry()
  var tagScrollMetrics = TagScrollMetrics()

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
      || (isComposerExpanded && (pendingComposerFocus != nil || composerFocused || quickDraft.isDirty))
      || submittingIDs.contains(quickDraft.creationID)
  }
  var isInteractionActive: Bool {
    isEditing || nativeTagDragActive || tagDropTarget != nil
  }
  var hasUnsavedEdits: Bool {
    if quickDrafts.values.contains(where: \.isDirty) || editDraft != nil { return true }
    guard let tagIntent else { return false }
    if case .delete = tagIntent.action { return false }
    return !tagIntent.name.isEmpty
  }
  var hasPendingSubmissions: Bool { !submittingIDs.isEmpty || pendingTagOrder != nil }
  var hasPendingTagDeletion: Bool {
    guard let intent = tagIntent, case .delete = intent.action else { return false }
    return submittingIDs.contains(intent.id)
  }

  func discardAllDrafts() {
    guard !hasPendingSubmissions else { return }
    quickDrafts = [:]
    editDraft = nil
    tagIntent = nil
    expandedComposers.removeAll()
    clearComposerFocus()
    ensureQuickDraft()
  }

  func hasDraftBlockingTagDeletion(_ id: UUID, document: LocalTaskDocument? = nil) -> Bool {
    if editedTaskAffectsTag(id, document: document) { return true }
    return quickDrafts.contains { origin, draft in
      draft.isDirty && (origin == .tag(id) || draft.selectedTagID == id)
    }
  }

  private func editedTaskAffectsTag(_ id: UUID, document: LocalTaskDocument?) -> Bool {
    guard let editDraft else { return false }
    if editDraft.selectedTagID == id { return true }
    guard let taskID = editDraft.taskID else { return false }
    // A changed draft destination does not move the stored task until Save.
    // Without confirmed storage, keep the edit protected rather than guessing.
    guard let document else { return true }
    return document.tasks.first(where: { $0.id == taskID })?.tagIDs.contains(id) == true
  }

  func needsCurrentEditFirst(forTagID id: UUID, document: LocalTaskDocument?) -> Bool {
    editDraft != nil && !editedTaskAffectsTag(id, document: document)
      && hasDraftBlockingTagDeletion(id, document: document)
  }

  /// Called before leaving the manager. Draft identity and every other list's
  /// draft are preserved; the caller only needs to reveal Home.
  func returnToDraft(affectedByTagID id: UUID, document: LocalTaskDocument? = nil) {
    tagIntent = nil
    // Home shows the active task editor before any quick entry. Resolve that
    // editor explicitly before changing selection to another retained draft.
    if editDraft != nil { return }
    let candidates = quickDrafts.filter { origin, draft in
      draft.isDirty && (origin == .tag(id) || draft.selectedTagID == id)
    }
    let origin =
      candidates.keys.first(where: { $0 == .tag(id) })
      ?? candidates.keys.sorted { String(describing: $0) < String(describing: $1) }.first
    guard let origin else { return }
    selectedFilter = origin
    beginAddingTask()
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
    pendingComposerFocus = focusRequest
    composerActivation.configureField()
  }
  func collapseComposer() {
    expandedComposers.remove(selectedFilter)
    expansionRevisions[selectedFilter, default: 0] += 1
    clearComposerFocus()
    composerActivation.configureField()
  }
  func confirmComposerFocus(_ focused: Bool, for request: UUID) {
    guard focusRequest == request, isComposerExpanded else { return }
    if composerFocused != focused { composerFocused = focused }
    if focused, pendingComposerFocus == request { pendingComposerFocus = nil }
  }
  func clearComposerFocus() {
    if pendingComposerFocus != nil { pendingComposerFocus = nil }
    if composerFocused { composerFocused = false }
  }
  func beginCreatingTag() {
    guard tagIntent == nil else { return }
    tagIntent = LocalTagIntent()
  }

  // MARK: - Tag drag and reorder

  func beginTagDrag(_ id: UUID, nativeSession: Bool = false) {
    nativeTagDragActive = nativeSession
    draggingTagID = id
    tagDropTarget = nil
  }

  func updateTagDrop(_ target: LocalTagDropTarget?) {
    guard tagDropTarget != target else { return }
    tagDropTarget = target
  }

  func endTagDrag() {
    if nativeTagDragActive { nativeTagDragActive = false }
    clearTagDragPreview()
  }

  private func clearTagDragPreview() {
    if draggingTagID != nil { draggingTagID = nil }
    updateTagDrop(nil)
  }

  /// Publishes the drop immediately and returns the store's `toIndex`.
  /// `nil` means the drop changed nothing and must not be persisted.
  func commitTagMove(_ id: UUID, to target: LocalTagDropTarget?, tagIDs: [UUID]) -> Int? {
    guard draggingTagID == id, let target else {
      clearTagDragPreview()
      return nil
    }
    return commitTagMove(id, toIndex: target.index, tagIDs: tagIDs)
  }

  /// The same optimistic publish for the keyboard and context-menu path, which
  /// has no caret geometry to hand over. Returns the store's `toIndex`, or
  /// `nil` when the requested slot is the tag's current one.
  func commitTagMove(_ id: UUID, toIndex: Int, tagIDs: [UUID]) -> Int? {
    defer { clearTagDragPreview() }
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

  /// Complete the write even when navigation has removed the tag bar and its
  /// document observer. A confirmed preview must never keep app exit pending.
  func finishTagMove(saved: Bool, tags: [TaskTag]) {
    if saved {
      reconcileTagOrder(tags)
    } else {
      abandonTagMove()
    }
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
    clearComposerFocus()
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
  func captureTagSubmission(document: LocalTaskDocument? = nil) -> LocalTagIntent? {
    guard let snapshot = tagIntent, !submittingIDs.contains(snapshot.id) else { return nil }
    if case .delete(let id) = snapshot.action,
      hasDraftBlockingTagDeletion(id, document: document)
    {
      return nil
    }
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
    if case .delete(let id) = snapshot.action {
      // Ending the old creation identity also rejects late field-editor writes.
      if quickDrafts[.tag(id)]?.isDirty != true { quickDrafts.removeValue(forKey: .tag(id)) }
      expandedComposers.remove(.tag(id))
    }
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
      clearComposerFocus()
      if let task { reveal(task, tags: tags) }
    }
  }
  func reveal(_ task: LocalTask, tags: [TaskTag]) {
    selectedFilter =
      tags.first(where: { task.tagIDs.contains($0.id) }).map { .tag($0.id) } ?? .untagged
    revealedTaskID = task.id
    revealRequest = UUID()
  }
  func revealRestoredDeletion(_ receipt: LocalDeletionReceipt, document: LocalTaskDocument) {
    // Undo never replaces an editor or any retained per-list quick draft.
    guard editDraft == nil else { return }
    switch receipt {
    case .task(let deletion):
      if let task = document.tasks.first(where: { $0.id == deletion.task.id }) {
        reveal(task, tags: document.tags)
      }
    case .tag(let deletion):
      guard document.tags.contains(where: { $0.id == deletion.tag.id }) else { return }
      selectedFilter = .tag(deletion.tag.id)
      revealedTaskID = deletion.tasks.first?.task.id
      revealRequest = UUID()
    }
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
  var onManageTags: () -> Void = {}
  @State private var tagScrollButtons = TagScrollMetrics.Buttons()
  @State private var dropCoordinator = TagBarDropCoordinator()
  @State private var rowHeight: CGFloat?
  @Environment(\.pulseReduceMotion) private var reduceMotion

  private var isInteracting: Bool { presentation.isInteractionActive }

  var body: some View {
    VStack(spacing: 0) {
      if let draft = presentation.editDraft {
        LocalTaskEditor(
          controller: controller, presentation: presentation,
          draft: Binding(
            get: { presentation.editDraft ?? draft },
            set: { value in
              guard presentation.editDraft?.creationID == draft.creationID else { return }
              presentation.editDraft = value
            })
        )
        .transition(.identity)
      } else {
        taskList
      }
      LocalDeletionUndoBar(controller: controller, presentation: presentation)
    }
    .onAppear {
      if let tags = controller.document?.tags {
        presentation.reconcileTags(tags)
        presentation.reconcileTagOrder(tags)
      }
      onEditingChanged(isInteracting)
    }
    .task {
      if controller.document == nil { await controller.refresh() }
      await controller.resetRepeatingTasks()
    }
    .onChange(of: isInteracting) { onEditingChanged($0) }
    .onDisappear {
      presentation.clearComposerFocus()
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
      tagBar(controller.document?.tags ?? [])
        .disabled(controller.document == nil)
      switch controller.initialLoadState {
      case .loaded:
        if presentation.tagIntent != nil {
          LocalTagEntry(controller: controller, presentation: presentation)
        }
        errorBanner.padding(.horizontal, PulseDesignTokens.contentInset)
        taskScrollView
      case .loading:
        initialTaskContent {
          Label {
            Text("Loading tasks")
          } icon: {
            PulseBusyGlyph(isBusy: true) { Image(systemName: "list.bullet") }
              .frame(width: 16, height: 16).accessibilityHidden(true)
          }
          .font(.caption).foregroundStyle(.secondary)
          .accessibilityIdentifier("loadingLocalTasks")
        }
      case .failed(let message):
        initialTaskContent {
          PulseErrorBanner(message: message, accessibilityIdentifier: "localTaskLoadError") {
            Button("Reload") { Task { await controller.refresh() } }
          }
        }
      }
    }
  }

  private func initialTaskContent<Content: View>(@ViewBuilder _ content: () -> Content)
    -> some View
  {
    content()
      .padding(TaskPaper.contentInset)
      .frame(maxWidth: .infinity, alignment: .leading)
      .modifier(TaskPaper())
      .padding(.horizontal, PulseDesignTokens.contentInset)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var taskScrollView: some View {
    let filter = presentation.selectedFilter
    let tasks = controller.tasks(matching: filter)
    let measuresRows = tasks.count < 12
    let emptyMessage = filter == .untagged ? "No tasks yet" : "No tasks in this tag"
    return VStack(spacing: 2) {
      ScrollViewReader { proxy in
        ScrollView {
          LocalTaskRows(
            tasks: tasks, pendingIDs: controller.pendingTaskIDs, emptyMessage: emptyMessage,
            controller: controller, presentation: presentation
          )
          .equatable()
          .frame(maxWidth: .infinity, alignment: .leading)
          .onGeometryChange(for: CGFloat?.self) { geometry in
            measuresRows ? ceil(geometry.size.height) : nil
          } action: { height in
            rowHeight = height
          }
        }
        .frame(maxHeight: measuresRows ? rowHeight : nil)
        .accessibilityIdentifier("localTaskList")
        .onAppear { scrollToRevealedTask(using: proxy) }
        .onChange(of: presentation.revealRequest) { _ in scrollToRevealedTask(using: proxy) }
      }
      LocalTaskQuickComposer(controller: controller, presentation: presentation)
    }
    .padding(TaskPaper.contentInset)
    .modifier(TaskPaper())
    .padding(.horizontal, PulseDesignTokens.contentInset)
    .padding(.vertical, 8)
    .frame(maxHeight: .infinity, alignment: .top)
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

  private func tagBar(_ tags: [TaskTag]) -> some View {
    let displayed = presentation.displayOrder(tags)
    let tagIDs = displayed.map(\.id)
    return HStack(spacing: 4) {
      PulsePillTab(
        title: "Todo", isSelected: presentation.selectedFilter == .untagged,
        action: { presentation.selectedFilter = .untagged }
      )
      .fixedSize(horizontal: true, vertical: false)
      .help("Default list · Tasks without a tag")
      .accessibilityIdentifier("localTaskFilter.todo")
      .anchorPreference(key: LocalTagBarBoundsKey.self, value: .bounds) { ["todo": $0] }
      ScrollViewReader { proxy in
        HStack(spacing: 0) {
          if tagScrollButtons.overflows {
            tagScrollButton(
              "chevron.left", label: "Previous tags", enabled: tagScrollButtons.hasPrevious
            ) {
              scrollTags(displayed, direction: -1, proxy: proxy)
            }
          }
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
              ForEach(displayed) { tag in tagPill(tag, tagIDs: tagIDs) }
            }
            .padding(.vertical, 4)
            .coordinateSpace(name: TagBarGeometry.spaceName)
            .onPreferenceChange(TagBarGeometryKey.self) { geometry in
              var measured = geometry
              measured.todoMidX = 0  // Todo is pinned outside this scrollable coordinate space.
              presentation.tagBarGeometry = measured
            }
            .background { NativeTagScrollMetricsReader(onChange: updateTagScrollMetrics) }
            .onDrop(of: [.text], delegate: dropCoordinator)
            .animation(
              reduceMotion ? nil : PulseDesignTokens.reorderAnimation,
              value: displayed.map(\.id))
          }
          .onChange(of: presentation.selectedFilter) { selection in
            guard selection != .untagged else { return }
            proxy.scrollTo(selection)
          }
          .onAppear { proxy.scrollTo(presentation.selectedFilter, anchor: .center) }
          .onChange(of: Set(tags.map(\.id))) { _ in
            proxy.scrollTo(presentation.selectedFilter, anchor: .center)
          }
          if tagScrollButtons.overflows {
            tagScrollButton(
              "chevron.right", label: "Next tags",
              enabled: tagScrollButtons.hasNext
            ) { scrollTags(displayed, direction: 1, proxy: proxy) }
          }
        }
      }
      Button {
        presentation.beginCreatingTag()
      } label: {
        Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
          .frame(width: 28, height: 28)
      }
      .buttonStyle(PulseIconButtonStyle()).help("New tag")
      .accessibilityLabel("New tag").accessibilityIdentifier("addLocalTagButton")
      .anchorPreference(key: LocalTagBarBoundsKey.self, value: .bounds) { ["add": $0] }
      Button(action: onManageTags) {
        Image(systemName: "list.bullet").font(.system(size: 13, weight: .medium))
          .frame(width: 28, height: 28)
      }
      .buttonStyle(PulseIconButtonStyle()).help("All tags")
      .accessibilityLabel("All tags").accessibilityIdentifier("manageLocalTagsButton")
      .anchorPreference(key: LocalTagBarBoundsKey.self, value: .bounds) { ["manage": $0] }
    }
    .padding(.horizontal, PulseDesignTokens.contentInset)
    .padding(.vertical, 6)
    .onAppear { configureDropCoordinator() }
  }

  private func tagScrollButton(
    _ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
        .frame(width: 18, height: 28)
    }
    .buttonStyle(PulseIconButtonStyle()).disabled(!enabled)
    .accessibilityLabel(PulseLocalization.string(label)).help(PulseLocalization.string(label))
    .accessibilityIdentifier(
      symbol == "chevron.left" ? "previousLocalTagsButton" : "nextLocalTagsButton"
    )
    .anchorPreference(key: LocalTagBarBoundsKey.self, value: .bounds) {
      [symbol == "chevron.left" ? "previous" : "next": $0]
    }
  }

  private func scrollTags(_ tags: [TaskTag], direction: Int, proxy: ScrollViewProxy) {
    let metrics = presentation.tagScrollMetrics
    let visibleCenter = -metrics.minX + metrics.viewportWidth / 2
    let target =
      direction > 0
      ? tags.first(where: { (presentation.tagBarGeometry.tagMidXByID[$0.id] ?? 0) > visibleCenter })
      : tags.last(where: { (presentation.tagBarGeometry.tagMidXByID[$0.id] ?? 0) < visibleCenter })
    guard let target else { return }
    withAnimation(reduceMotion ? nil : PulseDesignTokens.tabSwitchAnimation) {
      proxy.scrollTo(LocalTaskFilter.tag(target.id), anchor: direction > 0 ? .leading : .trailing)
    }
  }

  private func updateTagScrollMetrics(_ metrics: TagScrollMetrics) {
    presentation.tagScrollMetrics = metrics
    let buttons = TagScrollMetrics.Buttons(metrics: metrics)
    if tagScrollButtons != buttons { tagScrollButtons = buttons }
  }

  private func tagPill(_ tag: TaskTag, tagIDs: [UUID]) -> some View {
    let isDragging = presentation.draggingTagID == tag.id
    let selected = presentation.selectedFilter == .tag(tag.id)
    let index = tagIDs.firstIndex(of: tag.id) ?? 0
    let dropEdge =
      presentation.tagDropTarget?.pillID == tag.id ? presentation.tagDropTarget?.edge : nil
    return HStack(spacing: 0) {
      DraggableTagTab(
        source: NativeTagDragSource(
          tagID: tag.id, title: tag.name, isEnabled: !controller.isSaving,
          canMoveLeft: index > 0, canMoveRight: index < tagIDs.count - 1,
          onSelect: { presentation.selectedFilter = .tag(tag.id) },
          onBegin: {
            presentation.beginTagDrag(tag.id, nativeSession: true)
            onEditingChanged(presentation.isInteractionActive)
          },
          onMove: { deltaFromCenter in
            guard let midpoint = presentation.tagBarGeometry.tagMidXByID[tag.id] else { return }
            dropCoordinator.onLocation(CGPoint(x: midpoint + deltaFromCenter, y: 0))
          },
          onEnd: {
            presentation.endTagDrag()
            onEditingChanged(presentation.isInteractionActive)
          },
          onRename: {
            presentation.tagIntent = LocalTagIntent(action: .rename(tag.id), name: tag.name)
          },
          onDelete: {
            presentation.tagIntent = LocalTagIntent(action: .delete(tag.id), name: tag.name)
          },
          onMoveLeft: { moveTag(tag, in: tagIDs, to: index - 1) },
          onMoveRight: { moveTag(tag, in: tagIDs, to: index + 1) }
        ),
        isSelected: selected
      )
      .background(tagMidpointReporter { TagBarGeometry(tagMidXByID: [tag.id: $0]) })
      Menu {
        tagMenu(tag, tagIDs: tagIDs)
      } label: {
        Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
          .frame(width: 22, height: 28)
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden)
      .fixedSize().opacity(selected ? 1 : 0)
      .disabled(!selected || controller.isSaving)
      .accessibilityHidden(!selected)
      .accessibilityLabel("Actions for \(tag.name)")
      .accessibilityIdentifier("localTagActions.\(tag.id.uuidString)")
    }
    .id(LocalTaskFilter.tag(tag.id))
    .accessibilityIdentifier("localTaskFilter.\(tag.id.uuidString)")
    .contextMenu { tagMenu(tag, tagIDs: tagIDs) }
    .overlay(alignment: .leading) {
      if dropEdge == .leading { tagDropCaret.offset(x: -1) }
    }
    .overlay(alignment: .trailing) {
      if dropEdge == .trailing { tagDropCaret.offset(x: 1) }
    }
    .opacity(isDragging ? 0.5 : 1)
    .animation(reduceMotion ? nil : PulseDesignTokens.feedbackAnimation, value: isDragging)
    .accessibilityHint("Drag to reorder")
    .accessibilityAction(named: Text("Rename")) {
      presentation.tagIntent = LocalTagIntent(action: .rename(tag.id), name: tag.name)
    }
    .accessibilityAction(named: Text("Delete list")) {
      presentation.tagIntent = LocalTagIntent(action: .delete(tag.id), name: tag.name)
    }
    .accessibilityAction(named: Text("Move left")) { moveTag(tag, in: tagIDs, to: index - 1) }
    .accessibilityAction(named: Text("Move right")) { moveTag(tag, in: tagIDs, to: index + 1) }
  }

  @ViewBuilder private func tagMenu(_ tag: TaskTag, tagIDs: [UUID]) -> some View {
    let index = tagIDs.firstIndex(of: tag.id) ?? 0
    Button("Rename…") {
      presentation.tagIntent = LocalTagIntent(action: .rename(tag.id), name: tag.name)
    }
    Button("Delete list…", role: .destructive) {
      presentation.tagIntent = LocalTagIntent(action: .delete(tag.id), name: tag.name)
    }
    Divider()
    Button("Move Left") { moveTag(tag, in: tagIDs, to: index - 1) }
      .disabled(index == 0).keyboardShortcut(.leftArrow, modifiers: [.option, .command])
    Button("Move Right") { moveTag(tag, in: tagIDs, to: index + 1) }
      .disabled(index >= tagIDs.count - 1).keyboardShortcut(
        .rightArrow, modifiers: [.option, .command])
  }

  private var tagDropCaret: some View {
    Capsule()
      .fill(PulseDesignTokens.accent)
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
    dropCoordinator.isInternalDrag = {
      guard let id = presentation.draggingTagID else { return false }
      return presentation.nativeTagDragActive
        && controller.document?.tags.contains { $0.id == id } == true
    }
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
        presentation.finishTagMove(saved: saved, tags: controller.document?.tags ?? [])
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
      presentation.finishTagMove(saved: saved, tags: controller.document?.tags ?? [])
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

struct TaskWriteIndicator: View {
  let isBusy: Bool

  var body: some View {
    PulseBusyGlyph(isBusy: isBusy) { Color.clear }
      .frame(width: 16, height: 16)
      .foregroundStyle(.secondary)
      .accessibilityLabel("Saving")
      .accessibilityHidden(!isBusy)
  }
}

@MainActor
struct LocalDeletionUndoBar: View {
  @ObservedObject var controller: LocalTaskController
  @ObservedObject var presentation: LocalTaskPresentation

  var body: some View {
    if let receipt = controller.deletionHistory.last {
      VStack(spacing: 0) {
        Divider()
        HStack(spacing: 8) {
          Text(receipt.undoSummary).font(.caption).foregroundStyle(.secondary)
            .lineLimit(1).help(receipt.undoSummary)
            .pulseContentFeedback(receipt.undoSummary)
          Spacer(minLength: 0)
          TaskWriteIndicator(isBusy: controller.isUndoing)
          Button(receipt.undoButtonTitle) {
            Task {
              guard let receipt = controller.deletionHistory.last else { return }
              if await controller.undoDeletion(), let document = controller.document {
                presentation.revealRestoredDeletion(receipt, document: document)
              }
            }
          }
          .buttonStyle(PulseActionButtonStyle())
          .fixedSize()
          .disabled(controller.isSaving || controller.isUndoing)
          .help(receipt.undoHelp(availableCount: controller.deletionHistory.count))
          .accessibilityIdentifier("undoLocalTaskDeletionButton")
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
      }
      .transition(.identity)
      .accessibilityIdentifier("localDeletionUndoBar")
      .anchorPreference(key: LocalDeletionUndoBoundsKey.self, value: .bounds) { [$0] }
    }
  }
}

extension LocalDeletionReceipt {
  var undoSummary: String {
    switch self {
    case .task: PulseLocalization.string("Deleted task")
    case .tag(let receipt): PulseLocalization.format("Deleted list “%@”", receipt.tag.name)
    }
  }

  var undoButtonTitle: String {
    switch self {
    case .task: PulseLocalization.string("Undo task deletion")
    case .tag: PulseLocalization.string("Undo list deletion")
    }
  }

  func undoHelp(availableCount: Int) -> String {
    switch self {
    case .task:
      PulseLocalization.format("Restore the last deleted task (%lld available)", availableCount)
    case .tag:
      PulseLocalization.format(
        "Restore the last deleted list and its tasks (%lld available)", availableCount)
    }
  }
}

/// Passive layout evidence for the shared control on Home and both managers.
struct LocalDeletionUndoBoundsKey: PreferenceKey {
  static let defaultValue: [Anchor<CGRect>] = []
  static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
    value.append(contentsOf: nextValue())
  }
}

@MainActor
struct LocalTagEntry: View {
  @ObservedObject var controller: LocalTaskController
  @ObservedObject var presentation: LocalTaskPresentation
  var onReturnToDraft: () -> Void = {}
  @State private var focusRequest = UUID()
  private var intent: LocalTagIntent { presentation.tagIntent ?? LocalTagIntent() }
  private var tags: [TaskTag] { controller.document?.tags ?? [] }
  private var isSubmitting: Bool { presentation.submittingIDs.contains(intent.id) }
  private var existing: TaskTag? { intent.conflictingTag(in: tags) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if case .delete(let tagID) = intent.action {
        let taskCount = controller.document?.tasks.filter { $0.tagIDs.contains(tagID) }.count ?? 0
        let name = tags.first(where: { $0.id == tagID })?.name ?? intent.name
        let blocked = presentation.hasDraftBlockingTagDeletion(tagID, document: controller.document)
        Text(
          PulseLocalization.format(
            taskCount == 1
              ? "Delete “%@” and its %lld task?" : "Delete “%@” and its %lld tasks?", name,
            taskCount)
        )
        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        Text("The entire list will be deleted. Undo keeps the last 20 deletions until Pulse quits.")
          .font(.system(size: 12)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if blocked {
          let needsCurrentEdit = presentation.needsCurrentEditFirst(
            forTagID: tagID, document: controller.document)
          Text(
            LocalizedStringKey(
              needsCurrentEdit
                ? "You are editing another task. Save or cancel that edit first; this list’s draft will be kept."
                : "This list has an unfinished draft. Save or discard it before deleting the list.")
          )
          .font(.system(size: 12)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Button(LocalizedStringKey(needsCurrentEdit ? "Continue current edit" : "Return to draft"))
          {
            presentation.returnToDraft(affectedByTagID: tagID, document: controller.document)
            onReturnToDraft()
          }
          .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
          .accessibilityIdentifier("returnToBlockingTagDraftButton")
        }
        HStack {
          Button("Cancel") { presentation.tagIntent = nil }
          Spacer()
          TaskWriteIndicator(isBusy: isSubmitting)
          Button("Delete list", role: .destructive, action: submit)
            .disabled(blocked || controller.isSaving)
            .accessibilityIdentifier("confirmDeleteLocalTagButton")
        }
      } else {
        let intentID = intent.id
        HStack(spacing: 8) {
          TaskEntryField(
            text: Binding(
              get: {
                presentation.tagIntent?.id == intentID ? presentation.tagIntent?.name ?? "" : ""
              },
              set: {
                if presentation.tagIntent?.id == intentID { presentation.tagIntent?.name = $0 }
              }),
            placeholder: "Tag name", identifier: "newLocalTagNameField", focusRequest: focusRequest,
            isEnabled: !isSubmitting, onSubmit: submit, onFocusChanged: { _ in },
            onCancel: { presentation.tagIntent = nil }, editingID: intentID
          )
          .frame(height: 28)
          TaskWriteIndicator(isBusy: isSubmitting)
          Button(LocalizedStringKey(intent.action == .create ? "Create" : "Save"), action: submit)
            .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
            .disabled(!intent.hasValidName(in: tags) || controller.isSaving)
            .accessibilityIdentifier("saveLocalTagButton")
          Button("Cancel") { presentation.tagIntent = nil }
            .accessibilityIdentifier("cancelLocalTagButton")
        }
        if let existing {
          HStack {
            Text("This tag already exists.").foregroundStyle(.secondary)
            Button("Go to \(existing.name)") { useTag(existing.id) }
          }
        } else if LocalTaskStore.canonicalName(intent.name) == "todo" {
          HStack {
            Text("Todo is the default list.").foregroundStyle(.secondary)
            Button("Go to Todo") { useTag(nil) }
          }
        }
      }
    }
    .buttonStyle(PulseActionButtonStyle()).font(.system(size: 12))
    .padding(12)
    .background(PulseDesignTokens.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
    .padding(.horizontal, PulseDesignTokens.contentInset).padding(.vertical, 8)
    .disabled(isSubmitting)
    .accessibilityIdentifier("localTagEntry")
    .transition(.identity)
    .onAppear { focusRequest = UUID() }
    .onChange(of: presentation.tagIntent?.id) { _ in focusRequest = UUID() }
  }

  private func useTag(_ id: UUID?) {
    presentation.selectedFilter = id.map { .tag($0) } ?? .untagged
    presentation.tagIntent = nil
    controller.dismissError()
    onReturnToDraft()
  }

  private func submit() {
    guard !isSubmitting, !controller.isSaving else { return }
    if case .delete = intent.action {
      // Flush the native field before taking the deletion preflight snapshot.
      NSApp.keyWindow?.makeFirstResponder(nil)
    } else if !intent.hasValidName(in: tags) {
      return
    }
    guard let snapshot = presentation.captureTagSubmission(document: controller.document) else {
      return
    }
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
  @Environment(\.pulseReduceMotion) private var reduceMotion
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
      || presentation.hasPendingTagDeletion
  }
  private var listName: String {
    presentation.quickDraft.newTagNames.first
      ?? controller.document?.tags.first(where: { $0.id == presentation.quickDraft.selectedTagID })?
      .name ?? "Todo"
  }

  private var isExpanded: Bool { presentation.isComposerExpanded }

  private func entryField() -> TaskEntryField {
    let request = presentation.focusRequest
    let origin = presentation.selectedFilter
    let creationID = presentation.quickDraft.creationID
    let presenter = presentation
    return TaskEntryField(
      text: Binding(
        get: { presenter.quickDrafts[origin]?.text ?? "" },
        set: {
          guard presenter.selectedFilter == origin, presenter.isComposerExpanded,
            presenter.focusRequest == request, presenter.quickDrafts[origin]?.creationID == creationID,
            presenter.quickDrafts[origin]?.text != $0
          else { return }
          presenter.quickDrafts[origin]?.text = $0
        }),
      placeholder: PulseLocalization.format("Add to %@…", listName),
      identifier: "localTaskTextField",
      focusRequest: isExpanded ? presenter.pendingComposerFocus : nil,
      isEnabled: !isBusy, onSubmit: submit,
      onFocusChanged: { focused in
        guard presenter.selectedFilter == origin else { return }
        presenter.confirmComposerFocus(focused, for: request)
      },
      onCancel: { presenter.collapseComposer() },
      isShown: isExpanded, editingID: creationID,
      activation: presenter.composerActivation, configurationAfterActivation: entryField)
  }

  var body: some View {
    let origin = presentation.selectedFilter
    let request = presentation.focusRequest
    let escapeAction: (() -> Void)? = isExpanded ? { collapseFromKeyboard() } : nil
    let focusChanged: (Bool) -> Void = { focused in
      guard presentation.selectedFilter == origin else { return }
      presentation.confirmComposerFocus(focused, for: request)
    }
    VStack(alignment: .leading, spacing: 6) {
      ZStack {
        HStack(spacing: 6) {
          entryField().frame(height: 26)
            .accessibilityHidden(!isExpanded)
          if isExpanded {
            TaskWriteIndicator(isBusy: isBusy)
            Button("Add", action: submit)
              .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
              .disabled(
                isBusy
                  || presentation.quickDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
              )
              .help("Add task (Return)").accessibilityLabel("Add task").accessibilityIdentifier(
                "saveLocalTaskButton")
            Button {
              presentation.collapseComposer()
            } label: {
              Image(systemName: "xmark").font(.system(size: 11)).frame(width: 24, height: 26)
            }
            .buttonStyle(PulseIconButtonStyle()).help("Collapse input (Esc)")
            .accessibilityLabel("Collapse input").accessibilityIdentifier("collapseLocalTaskButton")
          }
        }
        if !isExpanded {
          TaskPaperAddButton(identifier: "addLocalTaskButton", action: presentation.beginAddingTask)
            .disabled(isBusy)
            .transition(.identity)
        }
      }
      .frame(minHeight: 32)
      if isExpanded {
        optionsBar
        if presentation.quickDraft.optionsExpanded {
          LocalTaskOptions(
            controller: controller, draft: draft,
            onFocusChanged: focusChanged,
            onCancel: { presentation.collapseComposer() }
          )
          .disabled(isBusy)
          .transition(.asymmetric(insertion: .opacity, removal: .identity))
        }
      }
    }
    .animation(
      reduceMotion ? nil : PulseDesignTokens.composerAnimation,
      value: presentation.quickDraft.optionsExpanded)
    .accessibilityIdentifier("localTaskInlineComposer")
    .onExitCommand(perform: escapeAction)
  }

  private func collapseFromKeyboard() {
    guard !presentation.composerActivation.isComposing else { return }
    presentation.collapseComposer()
  }

  private var optionsBar: some View {
    HStack {
      Button {
        presentation.quickDraft.optionsExpanded.toggle()
      } label: {
        Label("Options", systemImage: "slider.horizontal.3")
      }
      .buttonStyle(PulseActionButtonStyle()).disabled(isBusy)
      .accessibilityLabel("Task options").accessibilityIdentifier("localTaskOptionsButton")
      Spacer()
      Button("Discard draft") {
        let id = presentation.quickDraft.creationID
        presentation.finishDraft(id: id)
        presentation.collapseComposer()
      }
      .buttonStyle(PulseActionButtonStyle()).disabled(isBusy)
      .accessibilityIdentifier("discardLocalTaskDraftButton")
    }
  }
  private func submit() {
    guard !isBusy, presentation.composerActivation.finishInput() else { return }
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
            .pulseContentFeedback(listName)
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
        .transition(.identity)
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
        Text("Edit task").font(.system(size: 18, weight: .bold))
          .foregroundStyle(PulseDesignTokens.ink)
        Spacer(minLength: 0)
        HStack(spacing: 4) {
          TaskWriteIndicator(isBusy: isSubmitting)
          Button("Save", action: save)
            .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut("s", modifiers: .command)
            .accessibilityIdentifier("saveLocalTaskButton")
        }
        .frame(width: 60, alignment: .trailing)
      }
      .buttonStyle(.borderless).font(.system(size: 13))
      .padding(.horizontal, 16).padding(.vertical, 12)
      Rectangle().fill(PulseDesignTokens.border).frame(height: 1)
        .padding(.horizontal, PulseDesignTokens.contentInset)
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          TextEditor(text: $draft.text).font(.system(size: 15))
            .scrollContentBackground(.hidden)
            .foregroundStyle(PulseDesignTokens.ink)
            .frame(height: 148).padding(TaskPaper.contentInset)
            .modifier(TaskPaper())
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
private struct LocalTaskRows: View, Equatable {
  let tasks: [LocalTask]
  let pendingIDs: Set<UUID>
  let emptyMessage: String
  let controller: LocalTaskController
  let presentation: LocalTaskPresentation

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.controller === rhs.controller && lhs.presentation === rhs.presentation
      && lhs.tasks == rhs.tasks && lhs.pendingIDs == rhs.pendingIDs
      && (!lhs.tasks.isEmpty || lhs.emptyMessage == rhs.emptyMessage)
  }

  var body: some View {
    // Draft and focus updates keep the mounted list and drag surfaces stable.
    LazyVStack(alignment: .leading, spacing: 2) {
      if tasks.isEmpty {
        Text(LocalizedStringKey(emptyMessage))
          .font(.system(size: PulseDesignTokens.footnote))
          .foregroundStyle(PulseDesignTokens.muted)
          .padding(.vertical, 12)
      }
      ForEach(tasks) { task in
        LocalTaskRow(
          task: task, isPending: pendingIDs.contains(task.id),
          onToggle: { controller.setCompleted(!task.completed, taskID: task.id) },
          onEdit: { presentation.beginEditingTask(task) },
          onDelete: { Task { _ = await controller.deleteTask(id: task.id) } })
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
  var onDelete: (() -> Void)?
  @State private var isHovered = false
  private enum Control: Hashable { case complete, edit, delete }
  @FocusState private var focusedControl: Control?
  @Environment(\.pulseReduceMotion) private var reduceMotion

  var body: some View {
    HStack(alignment: .top, spacing: 2) {
      Button(action: onToggle) {
        PulseBusyGlyph(isBusy: isPending) {
          TaskCheckboxGlyph(completed: task.completed)
        }
        .frame(width: 16, height: 16).foregroundStyle(.secondary).accessibilityHidden(true)
        .padding(.top, 2).frame(width: 28, height: 30, alignment: .top).contentShape(Rectangle())
      }
      .buttonStyle(PulseRowButtonStyle(isHovered: isHovered)).disabled(isPending)
      .focused($focusedControl, equals: .complete)
      .help(PulseLocalization.string(task.completed ? "Mark incomplete" : "Mark complete"))
      .accessibilityLabel(
        PulseLocalization.format(
          task.completed ? "Mark incomplete: %@" : "Mark complete: %@", task.text)
      )
      .accessibilityValue(
        PulseLocalization.string(
          isPending ? "Saving" : (task.completed ? "Completed" : "Not completed"))
      )
      .accessibilityIdentifier("localTaskCheckbox.\(task.id.uuidString)")
      Button(action: onEdit) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(task.text).font(.system(size: 15))
            .foregroundStyle(task.completed ? PulseDesignTokens.muted : PulseDesignTokens.ink)
            .strikethrough(task.completed, color: PulseDesignTokens.muted)
            .animation(
              reduceMotion ? nil : PulseDesignTokens.completionAnimation, value: task.completed
            )
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
      .accessibilityValue(task.repeatsDaily ? PulseLocalization.string("Repeats daily") : "")
      .accessibilityIdentifier("localTaskText.\(task.id.uuidString)")
      if let onDelete {
        Button(action: onDelete) {
          Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
        }
        .buttonStyle(PulseIconButtonStyle()).disabled(isPending)
        .focused($focusedControl, equals: .delete)
        .opacity(isHovered || focusedControl != nil ? 1 : 0)
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: isHovered)
        .help("Delete task").accessibilityLabel("Delete task: \(task.text)")
        .accessibilityIdentifier("deleteLocalTaskRowButton.\(task.id.uuidString)")
      }
    }
    .onHover { isHovered = $0 }
    .contextMenu {
      Button("Edit task", action: onEdit).disabled(isPending)
      if let onDelete {
        Button("Delete task", role: .destructive, action: onDelete).disabled(isPending)
      }
    }
    .onDeleteCommand { if focusedControl != nil, !isPending { onDelete?() } }
  }
}

/// Connects a deliberate Add action to the already mounted native field.
@MainActor
final class TaskEntryActivation {
  weak var coordinator: TaskEntryField.Coordinator?

  var isComposing: Bool {
    (coordinator?.field?.window?.firstResponder as? NSTextView)?.hasMarkedText() == true
  }
  func configureField() { coordinator?.configureFromPresentation() }
  func finishInput() -> Bool { coordinator?.finishInput() ?? true }
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
  var isShown = true
  var editingID: UUID?
  var activation: TaskEntryActivation?
  var configurationAfterActivation: (() -> Self)?

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> FocusableTaskTextField {
    let field = FocusableTaskTextField()
    let coordinator = context.coordinator
    coordinator.field = field
    field.delegate = coordinator
    field.didAcquireEditor = { [weak coordinator] in coordinator?.reportFocus(true) }
    field.font = .systemFont(ofSize: identifier == "localTaskTextField" ? 15 : 13)
    field.isBezeled = true
    field.bezelStyle = .roundedBezel
    field.focusRingType = .none
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.setAccessibilityIdentifier(identifier)
    coordinator.configure(self, environmentEnabled: environmentEnabled)
    return field
  }

  func updateNSView(_ field: FocusableTaskTextField, context: Context) {
    context.coordinator.configure(
      configurationAfterActivation?() ?? self, environmentEnabled: environmentEnabled)
  }

  static func dismantleNSView(_ field: FocusableTaskTextField, coordinator: Coordinator) {
    coordinator.dismantle()
  }

  @MainActor
  final class Coordinator: NSObject, NSTextFieldDelegate {
    private var parent: TaskEntryField
    weak var field: FocusableTaskTextField?
    private var environmentEnabled = true
    private weak var activeEditor: NSTextView?
    private var configuring = false
    private var focusReport = 0
    private var reportedFocus: Bool?

    init(_ parent: TaskEntryField) { self.parent = parent }

    func configureFromPresentation() {
      guard let config = parent.configurationAfterActivation?() else { return }
      configure(config, environmentEnabled: environmentEnabled)
    }

    func finishInput() -> Bool {
      guard let field, field.ownsEditor else { return true }
      guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return false }
      updateText(from: field)
      return true
    }

    func configure(_ config: TaskEntryField, environmentEnabled: Bool) {
      guard let field else { return }
      self.environmentEnabled = environmentEnabled
      configuring = true
      defer { configuring = false }

      let isEnabled = config.isShown && config.isEnabled && environmentEnabled
      let newSession = parent.editingID != config.editingID
      if (newSession || !isEnabled), field.ownsEditor {
        field.window?.makeFirstResponder(nil)
        reportFocus(false)
      }
      if newSession {
        focusReport += 1
        reportedFocus = nil
      }
      parent = config
      config.activation?.coordinator = self

      // AppKit owns both the committed text and the marked text while editing.
      // Echo only into an inactive field, such as after restoring a retained draft.
      if field.currentEditor() == nil, field.stringValue != config.text {
        field.stringValue = config.text
      }
      if field.isHidden == config.isShown { field.isHidden = !config.isShown }
      if field.isEnabled != isEnabled { field.isEnabled = isEnabled }
      let placeholder = PulseLocalization.string(config.placeholder)
      if field.placeholderString != placeholder {
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
      }
      field.requestFocus(config.focusRequest)
    }

    func dismantle() {
      focusReport += 1
      stopObservingEditorUndo()
      if parent.activation?.coordinator === self { parent.activation?.coordinator = nil }
      field?.requestFocus(nil)
      field?.didAcquireEditor = nil
      field?.delegate = nil
      field = nil
    }

    func controlTextDidChange(_ notification: Notification) {
      guard !configuring, let field = notification.object as? NSTextField else { return }
      updateText(from: field)
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
      reportFocus(true)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
      stopObservingEditorUndo()
      reportFocus(false)
      guard !configuring, let field = notification.object as? NSTextField,
        let value = committedText(from: field), parent.text != value
      else { return }
      let expected = focusReport
      let binding = parent.$text
      // Ending an editor can be part of a navigation update. Apply a final
      // committed value only if a new editing session has not taken over.
      DispatchQueue.main.async { [weak self] in
        guard self?.focusReport == expected, binding.wrappedValue != value else { return }
        binding.wrappedValue = value
      }
    }

    private func committedText(from field: NSTextField) -> String? {
      let editor = field.currentEditor() as? NSTextView
      guard editor?.hasMarkedText() != true else { return nil }
      return editor?.string ?? field.stringValue
    }

    private func updateText(from field: NSTextField) {
      if let value = committedText(from: field), parent.text != value { parent.text = value }
    }

    func reportFocus(_ focused: Bool) {
      guard reportedFocus != focused else { return }
      reportedFocus = focused
      focusReport += 1
      if field != nil {
        // AppKit hands off synchronously, but SwiftUI publishers must wait
        // until the representable is out of its update pass.
        let expected = focusReport
        let callback = parent.onFocusChanged
        DispatchQueue.main.async { [weak self] in
          guard self?.focusReport == expected else { return }
          callback(focused)
        }
      } else {
        parent.onFocusChanged(focused)
      }
    }

    // The shared field editor can undo without sending controlTextDidChange.
    @objc private func editorUndoDidChange(_ notification: Notification) {
      guard !configuring, let activeEditor, !activeEditor.hasMarkedText() else { return }
      if parent.text != activeEditor.string { parent.text = activeEditor.string }
    }

    private func stopObservingEditorUndo() {
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
      if let field, control === field { updateText(from: field) }
      parent.onSubmit()
      return true
    }
  }
}

@MainActor
final class FocusableTaskTextField: NSTextField {
  private var requestedFocus: UUID?
  private var pendingFocus: UUID?
  var didAcquireEditor: (() -> Void)?

  var ownsEditor: Bool {
    guard let editor = currentEditor() else { return false }
    return window?.firstResponder === editor
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
    super.viewWillMove(toWindow: newWindow)
    if let newWindow {
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowDidBecomeKey(_:)),
        name: NSWindow.didBecomeKeyNotification, object: newWindow)
    }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyRequestedFocus()
  }

  func requestFocus(_ request: UUID?) {
    if request != requestedFocus {
      requestedFocus = request
      pendingFocus = request
    }
    applyRequestedFocus()
  }

  @objc private func windowDidBecomeKey(_ notification: Notification) { applyRequestedFocus() }

  private func applyRequestedFocus() {
    guard let request = pendingFocus, let window, isEnabled, !isHidden else { return }
    if !ownsEditor { window.makeFirstResponder(self) }
    guard ownsEditor, pendingFocus == request else { return }
    pendingFocus = nil
    didAcquireEditor?()
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
/// SwiftUI supplies drop acceptance/commit while the native source also reports
/// live position during edge autoscroll. Only our active native session is
/// accepted; an external text drag must never be acknowledged as a move.
@MainActor
final class TagBarDropCoordinator: DropDelegate {
  var isInternalDrag: () -> Bool = { false }
  var onLocation: (CGPoint) -> Void = { _ in }
  var onCommit: (CGPoint) -> Void = { _ in }
  var onExit: () -> Void = {}

  func validateDrop(info: DropInfo) -> Bool {
    isInternalDrag() && !info.itemProviders(for: [.text]).isEmpty
  }

  func dropEntered(info: DropInfo) { onLocation(info.location) }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard isInternalDrag() else { return nil }
    onLocation(info.location)
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) { onExit() }

  func performDrop(info: DropInfo) -> Bool {
    guard isInternalDrag() else { return false }
    onCommit(info.location)
    return true
  }
}

/// Passive anchors let rendering tests inspect the actual tag controls without
/// relying on SwiftUI's lazily generated accessibility tree in an XCTest host.
struct LocalTagBarBoundsKey: PreferenceKey {
  static let defaultValue: [String: Anchor<CGRect>] = [:]

  static func reduce(
    value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}
