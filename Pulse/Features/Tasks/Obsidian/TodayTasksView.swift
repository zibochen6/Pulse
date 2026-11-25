import SwiftUI

struct TodayTaskDraft {
  let id = UUID()
  var title = ""
  var focusRequest: UUID? = UUID()
}

/// Unsaved input belongs to the originating vault across panel closures and
/// changes in the paired vault.
@MainActor
final class TodayTaskPresentation: ObservableObject {
  @Published private(set) var drafts: [URL: TodayTaskDraft] = [:]
  @Published private(set) var actionErrors: [URL: String] = [:]
  @Published private(set) var submittingDrafts = Set<UUID>()
  @Published private(set) var focusedVault: URL?
  @Published private(set) var pendingFocusVault: URL?
  let composerActivation = TaskEntryActivation()

  var hasUnsavedEdits: Bool {
    drafts.values.contains { !$0.title.isEmpty }
  }

  var hasPendingSubmission: Bool { !submittingDrafts.isEmpty }

  func isEditing(in vault: URL) -> Bool {
    guard let draft = drafts[vault], draft.focusRequest != nil else { return false }
    return pendingFocusVault == vault || focusedVault == vault || !draft.title.isEmpty
      || submittingDrafts.contains(draft.id)
  }

  func setFocus(_ focused: Bool, in vault: URL, request: UUID? = nil) {
    if let request, drafts[vault]?.focusRequest != request { return }
    if focused {
      if focusedVault != vault { focusedVault = vault }
      if pendingFocusVault == vault { pendingFocusVault = nil }
    } else if focusedVault == vault {
      focusedVault = nil
    }
  }

  func clearComposerFocus(in vault: URL) {
    if pendingFocusVault == vault { pendingFocusVault = nil }
    setFocus(false, in: vault)
  }

  func beginDraft(in vault: URL) {
    if var draft = drafts[vault] {
      draft.focusRequest = UUID()
      drafts[vault] = draft
    } else {
      drafts[vault] = TodayTaskDraft()
    }
    pendingFocusVault = vault
    composerActivation.configureField()
  }

  func collapseDraft(in vault: URL) {
    drafts[vault]?.focusRequest = nil
    clearComposerFocus(in: vault)
    composerActivation.configureField()
  }

  func setTitle(_ title: String, in vault: URL, request: UUID) {
    guard let draft = drafts[vault], draft.focusRequest == request,
      draft.title != title, !submittingDrafts.contains(draft.id)
    else { return }
    drafts[vault]?.title = title
  }

  func discardDraft(in vault: URL) {
    guard let draft = drafts[vault], !submittingDrafts.contains(draft.id) else { return }
    drafts.removeValue(forKey: vault)
    clearComposerFocus(in: vault)
  }

  func discardAllDrafts() {
    guard !hasPendingSubmission else { return }
    drafts.removeAll()
    focusedVault = nil
    pendingFocusVault = nil
  }

  func clearError(in vault: URL) {
    actionErrors.removeValue(forKey: vault)
  }

  func perform(
    in vault: URL, bridge: TodayTaskBridge, action: @escaping @MainActor () async throws -> Void
  ) {
    clearError(in: vault)
    Task {
      guard bridge.vaultURL == vault else { return }
      do { try await action() } catch { actionErrors[vault] = error.localizedDescription }
    }
  }

  func submitDraft(in vault: URL, bridge: TodayTaskBridge) {
    guard let draft = drafts[vault], draft.focusRequest != nil,
      !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      submittingDrafts.insert(draft.id).inserted
    else { return }
    clearError(in: vault)
    Task {
      defer { submittingDrafts.remove(draft.id) }
      guard bridge.vaultURL == vault else { return }
      do {
        try await bridge.add(draft.title)
        if drafts[vault]?.id == draft.id {
          drafts.removeValue(forKey: vault)
          clearComposerFocus(in: vault)
        }
      } catch {
        actionErrors[vault] = error.localizedDescription
      }
    }
  }
}

@MainActor
struct HomeTaskLists: View {
  @ObservedObject var bridge: TodayTaskBridge
  @ObservedObject var presentation: TodayTaskPresentation
  let localTasks: LocalTaskController
  let localPresentation: LocalTaskPresentation
  let onEditingChanged: (Bool) -> Void
  let onManageTags: () -> Void
  var onTodayHeight: (URL?, CGFloat?) -> Void = { _, _ in }

  var body: some View {
    if let vault = bridge.vaultURL {
      TodayTasksView(
        vault: vault, bridge: bridge, presentation: presentation,
        onEditingChanged: onEditingChanged,
        onHeight: { onTodayHeight(vault, $0) }
      )
      .id(vault)
    } else {
      LocalTasksView(
        controller: localTasks, presentation: localPresentation,
        onEditingChanged: onEditingChanged, onManageTags: onManageTags
      )
      .onAppear { onTodayHeight(nil, nil) }
    }
  }
}

@MainActor
private struct TodayTasksView: View {
  let vault: URL
  @ObservedObject var bridge: TodayTaskBridge
  @ObservedObject var presentation: TodayTaskPresentation
  let onEditingChanged: (Bool) -> Void
  let onHeight: (CGFloat?) -> Void
  @State private var search = ""
  @State private var rowHeight: CGFloat?
  @State private var footerHeight: CGFloat?
  @FocusState private var searchFocused: Bool
  private static let headingLabelHeight: CGFloat = 28
  private static let headingInset: CGFloat = 6
  private static let bottomInset: CGFloat = 8
  private static let searchSpacing: CGFloat = 6
  private static var headingHeight: CGFloat {
    headingLabelHeight + 2 * headingInset
  }

  private var isEditing: Bool { presentation.isEditing(in: vault) || searchFocused }
  private var canQueue: Bool {
    bridge.connection != .protocolMismatch && bridge.connection != .storageUnavailable
  }
  private var canMeasureCompactHeight: Bool { bridge.tasks.count + bridge.failures.count < 12 }
  private var compactHeight: CGFloat? {
    guard canMeasureCompactHeight, let rowHeight, let footerHeight else { return nil }
    return Self.headingHeight + TaskListSearch.height + Self.searchSpacing + rowHeight
      + footerHeight + TaskPaper.contentInset * 2 + Self.bottomInset
  }

  var body: some View {
    let measuresRows = canMeasureCompactHeight
    VStack(spacing: 0) {
      heading
      TaskListSearch(text: $search, isFocused: $searchFocused, identifier: "searchTodayTasksField")
        .padding(.horizontal, PulseDesignTokens.contentInset)
        .padding(.bottom, Self.searchSpacing)
      VStack(spacing: 0) {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 3) { rows }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat?.self) { geometry in
              measuresRows ? ceil(geometry.size.height) : nil
            } action: { height in
              rowHeight = height
            }
        }
        .accessibilityIdentifier("obsidianTodayTaskList")
        .frame(maxHeight: measuresRows ? rowHeight : nil)
        composer
          .onGeometryChange(for: CGFloat?.self) { geometry in
            measuresRows ? ceil(geometry.size.height) : nil
          } action: { height in
            footerHeight = height
          }
      }
      .padding(TaskPaper.contentInset)
      .modifier(TaskPaper(folded: true))
      .padding(.horizontal, PulseDesignTokens.contentInset)
      .padding(.bottom, Self.bottomInset)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear {
      onEditingChanged(isEditing)
      onHeight(compactHeight)
    }
    .onChange(of: compactHeight, perform: onHeight)
    .onChange(of: isEditing) { onEditingChanged($0) }
    .onChange(of: canQueue) { if !$0 { presentation.clearComposerFocus(in: vault) } }
    .onDisappear {
      presentation.clearComposerFocus(in: vault)
      onEditingChanged(false)
    }
  }

  private var heading: some View {
    let completed = bridge.tasks.count(where: \.completed)
    return HStack(spacing: 8) {
      Text("Today Tasks")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(PulseDesignTokens.ink)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("todayTasksHeading")
      Spacer(minLength: 4)
      HStack(spacing: 4) {
        Text("Completed")
        let progress = "\(completed)/\(bridge.tasks.count)"
        Text(verbatim: progress).monospacedDigit().pulseContentFeedback(progress)
      }
      .font(.system(size: PulseDesignTokens.caption, weight: .medium))
      .foregroundStyle(PulseDesignTokens.muted)
      .accessibilityElement(children: .combine)
    }
    .frame(height: Self.headingLabelHeight)
    .padding(.horizontal, PulseDesignTokens.contentInset)
    .padding(.vertical, Self.headingInset)
  }

  @ViewBuilder private var rows: some View {
    let query = TaskListSearch.query(search)
    let allTasks = bridge.tasks
    let tasks =
      query.isEmpty ? allTasks : allTasks.filter { TaskListSearch.matches($0.title, query: query) }
    syncStatus
    if let message = presentation.actionErrors[vault] {
      PulseErrorBanner(message: message, accessibilityIdentifier: "todayTasksActionError") {
        Button("Dismiss") { presentation.clearError(in: vault) }
      }
    }
    ForEach(bridge.failures) { failure in
      PulseErrorBanner(
        message: PulseLocalization.format(
          "%@ — %@", failure.title, failure.todayTaskMessage)
      ) {
        if failure.canRetry {
          Button("Retry") { perform { try await bridge.retry(failure.id) } }
        }
        Button("Dismiss") { perform { try await bridge.dismissFailure(failure.id) } }
      }
      .accessibilityIdentifier("todayTaskFailure.\(failure.id)")
    }
    if tasks.isEmpty && (bridge.connection == .connected || !query.isEmpty) {
      Text(LocalizedStringKey(query.isEmpty ? "No tasks yet" : "No matching tasks"))
        .font(.system(size: PulseDesignTokens.footnote))
        .foregroundStyle(PulseDesignTokens.muted).padding(.vertical, 12)
    }
    ForEach(tasks) { task in
      TodayTaskRow(
        task: task, canQueue: canQueue,
        onToggle: {
          perform { try await bridge.setCompleted(!task.completed, taskID: task.id) }
        },
        onDelete: { perform { try await bridge.delete(taskID: task.id) } })
    }
  }

  @ViewBuilder private var syncStatus: some View {
    if bridge.connection != .connected || bridge.pendingCount > 0 {
      VStack(alignment: .leading, spacing: 3) {
        if bridge.connection != .connected {
          Text(bridge.connection.todayTaskMessage)
            .pulseContentFeedback(bridge.connection)
        }
        if bridge.pendingCount > 0 {
          Text(bridge.pendingStatus)
            .pulseContentFeedback(bridge.pendingStatus)
        }
      }
      .font(.system(size: PulseDesignTokens.caption))
      .foregroundStyle(PulseDesignTokens.muted)
      .padding(.vertical, 5)
      .transition(.identity)
      .accessibilityIdentifier("todayTasksSyncStatus")
    }
  }

  private func entryField() -> TaskEntryField {
    let request = bridge.vaultURL == vault ? presentation.drafts[vault]?.focusRequest : nil
    let presenter = presentation
    return TaskEntryField(
      text: Binding(
        get: { presenter.drafts[vault]?.title ?? "" },
        set: {
          guard let request, bridge.vaultURL == vault else { return }
          presenter.setTitle($0, in: vault, request: request)
        }),
      placeholder: "Add to Today…", identifier: "todayTaskTextField",
      focusRequest: presentation.pendingFocusVault == vault ? request : nil,
      isEnabled: canQueue && !isBusy, onSubmit: submit,
      onFocusChanged: { if let request { presenter.setFocus($0, in: vault, request: request) } },
      onCancel: { presenter.collapseDraft(in: vault) },
      isShown: request != nil, editingID: request,
      activation: presenter.composerActivation, configurationAfterActivation: entryField)
  }

  private var isBusy: Bool {
    guard let draft = presentation.drafts[vault] else { return false }
    return presentation.submittingDrafts.contains(draft.id)
  }

  private var composer: some View {
    let draft = presentation.drafts[vault]
    let isExpanded = draft?.focusRequest != nil
    let escapeAction: (() -> Void)? = isExpanded ? { collapseFromKeyboard() } : nil
    return VStack(alignment: .trailing, spacing: 4) {
      ZStack {
        HStack(spacing: 6) {
          entryField().frame(height: 26)
            .accessibilityHidden(!isExpanded)
          if isExpanded {
            TaskWriteIndicator(isBusy: isBusy)
            Button("Add", action: submit)
              .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
              .disabled(
                !canQueue || isBusy
                  || draft?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
              )
              .help("Add task (Return)")
              .accessibilityLabel("Add task").accessibilityIdentifier("saveTodayTaskButton")
            Button {
              presentation.collapseDraft(in: vault)
            } label: {
              Image(systemName: "xmark").font(.system(size: 11))
            }
            .buttonStyle(PulseIconButtonStyle())
            .help("Collapse input (Esc)").accessibilityLabel("Collapse input")
            .accessibilityIdentifier("collapseTodayTaskButton")
          }
        }
        if !isExpanded {
          TaskPaperAddButton(identifier: "addTodayTaskButton") {
            presentation.beginDraft(in: vault)
          }
          .disabled(!canQueue || isBusy)
          .transition(.identity)
        }
      }
      .frame(minHeight: 32)
      if isExpanded, draft?.title.isEmpty == false {
        Button("Discard draft") { presentation.discardDraft(in: vault) }
          .buttonStyle(.borderless).font(.system(size: PulseDesignTokens.caption))
          .disabled(isBusy)
      }
    }
    .onExitCommand(perform: escapeAction)
  }

  private func collapseFromKeyboard() {
    guard !presentation.composerActivation.isComposing else { return }
    presentation.collapseDraft(in: vault)
  }

  private func submit() {
    guard canQueue, presentation.composerActivation.finishInput() else { return }
    presentation.submitDraft(in: vault, bridge: bridge)
  }

  private func perform(_ action: @escaping @MainActor () async throws -> Void) {
    presentation.perform(in: vault, bridge: bridge, action: action)
  }
}

private struct TodayTaskRow: View {
  let task: TodayBridgeTask
  let canQueue: Bool
  let onToggle: () -> Void
  let onDelete: () -> Void
  @Environment(\.pulseReduceMotion) private var reduceMotion
  @State private var hovered = false
  @FocusState private var deleteFocused: Bool

  private var isEditable: Bool { canQueue && !task.isPending }
  private var deleteTitle: String { task.source == .quick ? "Delete task" : "Remove from Today" }

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Button(action: onToggle) {
        TaskCheckboxGlyph(completed: task.completed)
      }
      .buttonStyle(PulseIconButtonStyle()).disabled(!isEditable)
      .help(PulseLocalization.string(task.completed ? "Mark incomplete" : "Mark complete"))
      .accessibilityLabel(
        PulseLocalization.format(
          task.completed ? "Mark incomplete: %@" : "Mark complete: %@", task.title)
      )
      .accessibilityValue(
        PulseLocalization.string(
          task.isPending ? "Waiting to sync" : (task.completed ? "Completed" : "Not completed"))
      )
      .accessibilityIdentifier("todayTaskCheckbox.\(task.id)")
      Text(task.title).font(.system(size: 15))
        .foregroundStyle(task.completed ? PulseDesignTokens.muted : PulseDesignTokens.ink)
        .strikethrough(task.completed, color: PulseDesignTokens.muted)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .animation(
          reduceMotion ? nil : PulseDesignTokens.completionAnimation, value: task.completed)
      ZStack {
        Button(action: onDelete) {
          Image(systemName: task.source == .quick ? "trash" : "calendar.badge.minus")
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .buttonStyle(PulseIconButtonStyle()).disabled(!isEditable)
        .focused($deleteFocused)
        .opacity(!task.isPending && (hovered || deleteFocused) ? 1 : 0)
        .animation(reduceMotion ? nil : PulseDesignTokens.hoverAnimation, value: hovered)
        .accessibilityHidden(task.isPending)
        .help(PulseLocalization.string(deleteTitle))
        .accessibilityLabel(
          PulseLocalization.format(
            task.source == .quick ? "Delete task: %@" : "Remove from Today: %@", task.title)
        )
        .accessibilityIdentifier("deleteTodayTaskButton.\(task.id)")
        if task.isPending {
          Image(systemName: "clock").font(.system(size: 12))
            .foregroundStyle(.secondary)
            .help("Waiting to sync").accessibilityLabel("Waiting to sync")
            .transition(.identity)
        }
      }
      .frame(width: 28, height: 28)
    }
    .contentShape(Rectangle())
    .onHover { hovered = $0 }
    .contextMenu {
      Button(
        PulseLocalization.string(deleteTitle),
        role: task.source == .quick ? .destructive : nil, action: onDelete
      )
      .disabled(!isEditable)
    }
  }
}

struct TaskPaper: ViewModifier {
  static let contentInset: CGFloat = 10
  var folded = false
  @Environment(\.pulsePaperOpacity) private var paperOpacity

  func body(content: Content) -> some View {
    let outline = TaskPaperOutline(folded: folded)
    content
      .background(PulseDesignTokens.taskPaper.opacity(paperOpacity), in: outline)
      .overlay(alignment: .topTrailing) {
        if folded {
          TaskPaperCorner()
            .fill(PulseDesignTokens.taskFold)
            .frame(width: TaskPaperOutline.foldSize, height: TaskPaperOutline.foldSize)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
      }
      .overlay {
        outline.stroke(PulseDesignTokens.border, lineWidth: 1)
          .allowsHitTesting(false)
      }
  }
}

private struct TaskPaperOutline: Shape {
  static let foldSize: CGFloat = 14
  let folded: Bool

  func path(in rect: CGRect) -> Path {
    let radius = PulseDesignTokens.cornerLarge
    guard folded else { return RoundedRectangle(cornerRadius: radius).path(in: rect) }
    let fold = min(Self.foldSize, rect.width, rect.height)
    let small = min(4, rect.width / 2, rect.height / 2)
    let bottom = min(radius, rect.width / 2, max(0, rect.height - fold))
    return Path { path in
      path.move(to: CGPoint(x: rect.minX + small, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
      path.addQuadCurve(
        to: CGPoint(x: rect.maxX - bottom, y: rect.maxY),
        control: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX + small, y: rect.maxY))
      path.addQuadCurve(
        to: CGPoint(x: rect.minX, y: rect.maxY - small),
        control: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + small))
      path.addQuadCurve(
        to: CGPoint(x: rect.minX + small, y: rect.minY),
        control: CGPoint(x: rect.minX, y: rect.minY))
      path.closeSubpath()
    }
  }
}

private struct TaskPaperCorner: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.closeSubpath()
    }
  }
}

struct TaskListSearch: View {
  static let height: CGFloat = 28
  @Binding var text: String
  @FocusState.Binding var isFocused: Bool
  let identifier: String

  static func query(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func matches(_ title: String, query: String) -> Bool {
    query.isEmpty || title.localizedStandardContains(query)
  }

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: PulseDesignTokens.caption))
        .foregroundStyle(PulseDesignTokens.muted)
        .accessibilityHidden(true)
      TextField("Search tasks", text: $text)
        .textFieldStyle(.plain)
        .font(.system(size: PulseDesignTokens.footnote))
        .focused($isFocused)
        .accessibilityIdentifier(identifier)
      Button {
        text = ""
        isFocused = true
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: PulseDesignTokens.caption))
          .foregroundStyle(PulseDesignTokens.muted)
      }
      .buttonStyle(.borderless)
      .help("Clear search").accessibilityLabel("Clear search")
      .opacity(text.isEmpty ? 0 : 1)
      .disabled(text.isEmpty)
      .accessibilityHidden(text.isEmpty)
    }
    .padding(.horizontal, 9)
    .frame(height: Self.height)
    .pulsePaper(PulseDesignTokens.secondarySurface)
  }
}

struct TaskPaperAddButton: View {
  let identifier: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(PulseDesignTokens.ink)
    }
    .buttonStyle(PulseIconButtonStyle(circular: true))
    .help("Add task")
    .accessibilityLabel("Add task")
    .accessibilityIdentifier(identifier)
    .frame(maxWidth: .infinity)
    .padding(.top, 4)
  }
}

struct TaskCheckboxGlyph: View {
  let completed: Bool
  @Environment(\.pulseReduceMotion) private var reduceMotion

  var body: some View {
    let square = RoundedRectangle(cornerRadius: 3)
    ZStack {
      square.strokeBorder(PulseDesignTokens.ink, lineWidth: 1.25).opacity(completed ? 0 : 1)
      square.fill(PulseDesignTokens.success)
        .overlay {
          Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(PulseDesignTokens.background)
        }
        .opacity(completed ? 1 : 0)
    }
    .frame(width: 16, height: 16)
    .animation(reduceMotion ? nil : PulseDesignTokens.completionAnimation, value: completed)
    .accessibilityHidden(true)
  }
}

extension TodayTaskBridge {
  var pendingStatus: String {
    PulseLocalization.format(
      pendingCount == 1 ? "%lld change waiting to sync" : "%lld changes waiting to sync",
      pendingCount)
  }
}

extension TodayBridgeConnection {
  var todayTaskMessage: String {
    switch self {
    case .off: PulseLocalization.string("Not connected")
    case .waiting: PulseLocalization.string("Waiting for Obsidian")
    case .connected: PulseLocalization.string("Connected")
    case .sourceUnavailable:
      PulseLocalization.string("Obsidian could not read the Today Tasks sources.")
    case .protocolMismatch:
      PulseLocalization.string("Update Pulse or the Personal Dashboard plugin to sync.")
    case .storageUnavailable:
      PulseLocalization.string("Pulse could not access the local Obsidian sync files.")
    }
  }
}

extension TodayBridgeFailure {
  var todayTaskMessage: String {
    switch code {
    case .conflict:
      PulseLocalization.string("This task changed in Obsidian. Review it and try again.")
    case .expired: PulseLocalization.string("This change was queued on a previous day.")
    case .unsafeDelete:
      PulseLocalization.string("This task needs to be deleted in its source note.")
    case .invalid: PulseLocalization.string("Obsidian could not apply this change.")
    }
  }
}
