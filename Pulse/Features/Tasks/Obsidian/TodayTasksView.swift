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

  var hasUnsavedEdits: Bool {
    drafts.values.contains { !$0.title.isEmpty }
  }

  var hasPendingSubmission: Bool { !submittingDrafts.isEmpty }

  func isEditing(in vault: URL) -> Bool {
    guard let draft = drafts[vault], draft.focusRequest != nil else { return false }
    return focusedVault == vault || !draft.title.isEmpty || submittingDrafts.contains(draft.id)
  }

  func setFocus(_ focused: Bool, in vault: URL, request: UUID? = nil) {
    if let request, drafts[vault]?.focusRequest != request { return }
    if focused {
      focusedVault = vault
    } else if focusedVault == vault {
      focusedVault = nil
    }
  }

  func beginDraft(in vault: URL) {
    if var draft = drafts[vault] {
      draft.focusRequest = UUID()
      drafts[vault] = draft
    } else {
      drafts[vault] = TodayTaskDraft()
    }
  }

  func collapseDraft(in vault: URL) {
    drafts[vault]?.focusRequest = nil
    setFocus(false, in: vault)
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
    setFocus(false, in: vault)
  }

  func discardAllDrafts() {
    guard !hasPendingSubmission else { return }
    drafts.removeAll()
    focusedVault = nil
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
          setFocus(false, in: vault)
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
  var onTodayHeight: (CGFloat?) -> Void = { _ in }

  var body: some View {
    if let vault = bridge.vaultURL {
      TodayTasksView(
        vault: vault, bridge: bridge, presentation: presentation,
        onEditingChanged: onEditingChanged,
        onHeight: onTodayHeight
      )
      .id(vault)
    } else {
      LocalTasksView(
        controller: localTasks, presentation: localPresentation,
        onEditingChanged: onEditingChanged, onManageTags: onManageTags
      )
      .onAppear { onTodayHeight(nil) }
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
  private static let headingLabelHeight: CGFloat = 28
  private static let headingInset: CGFloat = 6
  private static let bottomInset: CGFloat = 8
  private static var headingHeight: CGFloat {
    headingLabelHeight + 2 * headingInset
  }

  private var isEditing: Bool { presentation.isEditing(in: vault) }
  private var canQueue: Bool {
    bridge.connection != .protocolMismatch && bridge.connection != .storageUnavailable
  }

  var body: some View {
    VStack(spacing: 0) {
      heading
      ScrollViewReader { proxy in
        ScrollView {
          if bridge.tasks.count + bridge.failures.count >= 12 {
            LazyVStack(alignment: .leading, spacing: 3) { rows }
              .padding(TaskPaper.contentInset)
              .frame(maxWidth: .infinity, alignment: .leading)
              .onAppear { onHeight(nil) }
          } else {
            VStack(alignment: .leading, spacing: 3) { rows }
              .padding(TaskPaper.contentInset)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background {
                GeometryReader { geometry in
                  Color.clear
                    .onAppear { reportContentHeight(geometry.size.height) }
                    .onChange(of: geometry.size.height, perform: reportContentHeight)
                }
              }
          }
        }
        .task(id: presentation.drafts[vault]?.focusRequest) {
          guard let request = presentation.drafts[vault]?.focusRequest else { return }
          await Task.yield()
          guard !Task.isCancelled, presentation.drafts[vault]?.focusRequest == request else {
            return
          }
          proxy.scrollTo("todayComposer", anchor: .bottom)
        }
      }
      .accessibilityIdentifier("obsidianTodayTaskList")
      .modifier(TaskPaper(folded: true))
      .padding(.horizontal, PulseDesignTokens.contentInset)
      .padding(.bottom, Self.bottomInset)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear { onEditingChanged(isEditing) }
    .onChange(of: isEditing) { onEditingChanged($0) }
    .onDisappear {
      presentation.setFocus(false, in: vault)
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
        Text(verbatim: "\(completed)/\(bridge.tasks.count)").monospacedDigit()
      }
      .font(.system(size: PulseDesignTokens.caption, weight: .medium))
      .foregroundStyle(PulseDesignTokens.muted)
      .accessibilityElement(children: .combine)
    }
    .frame(height: Self.headingLabelHeight)
    .padding(.horizontal, PulseDesignTokens.contentInset)
    .padding(.vertical, Self.headingInset)
  }

  private func reportContentHeight(_ height: CGFloat) {
    onHeight(Self.headingHeight + height + Self.bottomInset)
  }

  @ViewBuilder private var rows: some View {
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
    if bridge.connection == .connected && bridge.tasks.isEmpty {
      Text("No tasks yet").font(.system(size: PulseDesignTokens.footnote))
        .foregroundStyle(PulseDesignTokens.muted).padding(.vertical, 12)
    }
    ForEach(bridge.tasks) { task in
      TodayTaskRow(
        task: task, canQueue: canQueue,
        onToggle: {
          perform { try await bridge.setCompleted(!task.completed, taskID: task.id) }
        },
        onDelete: { perform { try await bridge.delete(taskID: task.id) } })
    }
    composer
      .id("todayComposer")
  }

  @ViewBuilder private var syncStatus: some View {
    if bridge.connection != .connected || bridge.pendingCount > 0 {
      VStack(alignment: .leading, spacing: 3) {
        if bridge.connection != .connected {
          Text(bridge.connection.todayTaskMessage)
        }
        if bridge.pendingCount > 0 {
          Text(bridge.pendingStatus)
        }
      }
      .font(.system(size: PulseDesignTokens.caption))
      .foregroundStyle(PulseDesignTokens.muted)
      .padding(.vertical, 5)
      .accessibilityIdentifier("todayTasksSyncStatus")
    }
  }

  @ViewBuilder private var composer: some View {
    if let draft = presentation.drafts[vault], let request = draft.focusRequest {
      let busy = presentation.submittingDrafts.contains(draft.id)
      let enabled = canQueue && !busy
      VStack(alignment: .trailing, spacing: 4) {
        HStack(spacing: 6) {
          TaskEntryField(
            text: Binding(
              get: { presentation.drafts[vault]?.title ?? "" },
              set: { presentation.setTitle($0, in: vault, request: request) }),
            placeholder: "Add to Today…", identifier: "todayTaskTextField",
            focusRequest: request, isEnabled: enabled, onSubmit: submit,
            onFocusChanged: { presentation.setFocus($0, in: vault, request: request) },
            onCancel: { presentation.collapseDraft(in: vault) }
          )
          .frame(height: 26)
          Button("Add", action: submit)
            .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
            .disabled(
              !enabled || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        if !draft.title.isEmpty {
          Button("Discard draft") { presentation.discardDraft(in: vault) }
            .buttonStyle(.borderless).font(.system(size: PulseDesignTokens.caption))
            .disabled(busy)
        }
      }
      .padding(.vertical, 6)
      .onExitCommand { presentation.collapseDraft(in: vault) }
    } else {
      TaskPaperAddButton(identifier: "addTodayTaskButton") {
        presentation.beginDraft(in: vault)
      }
      .disabled(!canQueue)
    }
  }

  private func submit() {
    guard canQueue else { return }
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
      if task.isPending {
        Image(systemName: "clock").font(.system(size: 12))
          .foregroundStyle(.secondary).frame(width: 28, height: 28)
          .help("Waiting to sync").accessibilityLabel("Waiting to sync")
      } else {
        Button(action: onDelete) {
          Image(systemName: task.source == .quick ? "trash" : "calendar.badge.minus")
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .buttonStyle(PulseIconButtonStyle()).disabled(!isEditable)
        .focused($deleteFocused)
        .opacity(hovered || deleteFocused ? 1 : 0)
        .help(PulseLocalization.string(deleteTitle))
        .accessibilityLabel(
          PulseLocalization.format(
            task.source == .quick ? "Delete task: %@" : "Remove from Today: %@", task.title)
        )
        .accessibilityIdentifier("deleteTodayTaskButton.\(task.id)")
      }
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

  func body(content: Content) -> some View {
    let outline = TaskPaperOutline(folded: folded)
    content
      .background(PulseDesignTokens.taskPaper, in: outline)
      .clipShape(outline)
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
        .scaleEffect(reduceMotion || completed ? 1 : 0.9)
        .opacity(completed ? 1 : 0)
    }
    .frame(width: 16, height: 16)
    .animation(reduceMotion ? nil : PulseDesignTokens.selectionAnimation, value: completed)
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
