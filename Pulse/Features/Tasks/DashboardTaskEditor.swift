import SwiftUI

/// Lives above navigation, retaining unsaved input when the popover is dismissed.
@MainActor
final class DashboardTaskPresentation: ObservableObject {
  @Published var selectedColumnTitle: String?
  @Published var draft: DashboardTaskDraft?
  private var displayedFileURL: URL?
  private var displayedSelectionGeneration: Int?

  var isEditing: Bool { draft != nil }

  func beginAdding(in dashboard: Dashboard) {
    reconcileFile(dashboard.fileURL)
    let column =
      dashboard.columns.first(where: { $0.title == selectedColumnTitle })
      ?? dashboard.columns.first
    draft = DashboardTaskDraft(
      snapshot: dashboard,
      columnOrder: column?.sourceOrder ?? 0,
      cardOrder: column?.cards.first?.sourceOrder)
  }

  func finishDraft(id: UUID) {
    guard draft?.id == id else { return }
    draft = nil
  }

  func didSave(_ request: DashboardTaskCreationRequest) {
    guard draft?.id == request.id else { return }
    selectedColumnTitle = request.destination.columnTitle
    draft = nil
  }

  func reconcileSelection(_ generation: Int) {
    if let previous = displayedSelectionGeneration, previous != generation {
      draft = nil
      selectedColumnTitle = nil
      displayedFileURL = nil
    }
    displayedSelectionGeneration = generation
  }

  func reconcileFile(_ fileURL: URL) {
    let current = fileURL.standardizedFileURL
    let displayedFileChanged = displayedFileURL.map { $0 != current } ?? false
    let draftFileChanged = draft.map { $0.snapshot.fileURL.standardizedFileURL != current } ?? false
    if displayedFileChanged || draftFileChanged {
      draft = nil
      selectedColumnTitle = nil
    }
    displayedFileURL = current
  }
}

struct DashboardTaskDraft {
  let id = UUID()
  let snapshot: Dashboard
  var columnOrder: Int
  var cardOrder: Int?
  var text = ""
  var tags: [String] = []
  var newTagText = ""

  var column: DashboardColumn? {
    snapshot.columns.first(where: { $0.sourceOrder == columnOrder })
  }
  var card: DashboardCard? {
    column?.cards.first(where: { $0.sourceOrder == cardOrder })
  }
  var request: DashboardTaskCreationRequest? {
    guard let column, let card,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    let existing = Set(DashboardTaskTags.extract(from: text).map { $0.lowercased() })
    let missing = tags.filter { !existing.contains($0.lowercased()) }
    let suffix = missing.map { "#\($0)" }.joined(separator: " ")
    let taskText = text.trimmingCharacters(in: .whitespaces)
    return DashboardTaskCreationRequest(
      id: id, text: taskText + (suffix.isEmpty ? "" : " " + suffix),
      destination: DashboardTaskDestination(column: column, card: card),
      snapshot: snapshot)
  }

  var availableTags: [String] {
    DashboardTaskTags.unique(
      snapshot.allTasks.flatMap { DashboardTaskTags.extract(from: $0.text) } + tags)
  }

  @discardableResult
  mutating func addTag(_ input: String) -> Bool {
    guard let name = DashboardTaskTags.normalized(input) else { return false }
    if !tags.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
      tags.append(name)
    }
    newTagText = ""
    return true
  }
}

/// Only plain hashtag suggestions for creation, not a Markdown/task parser.
enum DashboardTaskTags {
  static func normalized(_ input: String) -> String? {
    var name = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.hasPrefix("#") { name.removeFirst() }
    guard !name.isEmpty,
      name.unicodeScalars.allSatisfy({ scalar in
        CharacterSet.alphanumerics.contains(scalar)
          || CharacterSet.nonBaseCharacters.contains(scalar)
          || CharacterSet.symbols.contains(scalar)
          || "_-/".unicodeScalars.contains(scalar) || scalar.value == 0x200D
      }),
      name.unicodeScalars.contains(where: { !CharacterSet.decimalDigits.contains($0) })
    else { return nil }
    return name
  }

  static func extract(from text: String) -> [String] {
    unique(
      text.split(whereSeparator: { $0.isWhitespace }).compactMap { token in
        token.hasPrefix("#") ? normalized(String(token)) : nil
      })
  }

  static func unique(_ tags: [String]) -> [String] {
    var seen = Set<String>()
    return tags.filter { seen.insert($0.lowercased()).inserted }
  }
}

@MainActor
struct DashboardTaskEditor: View {
  @ObservedObject var controller: DashboardTaskController
  @ObservedObject var presentation: DashboardTaskPresentation
  @Binding var draft: DashboardTaskDraft
  let onConfigure: () -> Void

  @FocusState private var textFocused: Bool
  @State private var tagError: String?
  private var isBusy: Bool { controller.isAddingTask }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .top, spacing: 6) {
        TextField("Add a task…", text: $draft.text, axis: .vertical)
          .font(.system(size: 15))
          .textFieldStyle(.roundedBorder)
          .lineLimit(1...2)
          .focused($textFocused)
          .onSubmit(submit)
          .accessibilityLabel("New Obsidian task text")
          .accessibilityIdentifier("dashboardNewTaskTextField")
        if isBusy { ProgressView().controlSize(.mini).padding(.top, 5) }
        Button(action: submit) { Image(systemName: "arrow.up") }
          .buttonStyle(PulseActionButtonStyle(emphasis: .primary))
          .disabled(
            isBusy || draft.card == nil
              || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
          .keyboardShortcut("s", modifiers: .command)
          .help("Add task")
          .accessibilityLabel("Add task to Dashboard")
          .accessibilityIdentifier("saveDashboardTaskButton")
        Button {
          presentation.finishDraft(id: draft.id)
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(PulseActionButtonStyle())
        .disabled(isBusy)
        .keyboardShortcut(.cancelAction)
        .help("Cancel")
        .accessibilityLabel("Cancel new task")
        .accessibilityIdentifier("cancelDashboardTaskButton")
      }
      .disabled(isBusy)

      HStack(spacing: 8) {
        Picker("Column", selection: $draft.columnOrder) {
          ForEach(draft.snapshot.columns) { column in
            Text(column.title).tag(column.sourceOrder)
          }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Task column")
        .accessibilityIdentifier("dashboardTaskColumnPicker")
        .onChange(of: draft.columnOrder) { _ in
          draft.cardOrder = draft.column?.cards.first?.sourceOrder
        }
        if let column = draft.column, !column.cards.isEmpty {
          Picker("Group", selection: $draft.cardOrder) {
            ForEach(column.cards) { card in
              Text(cardLabel(card, in: column)).tag(Optional(card.sourceOrder))
            }
          }
          .labelsHidden()
          .frame(maxWidth: .infinity)
          .accessibilityLabel("Task group")
          .accessibilityIdentifier("dashboardTaskCardPicker")
        }
      }
      .font(.system(size: 12))
      .disabled(isBusy)

      HStack(spacing: 8) {
        Menu {
          if draft.availableTags.isEmpty {
            Text("No tags in this Dashboard")
          }
          ForEach(draft.availableTags, id: \.self) { tag in
            Toggle(
              "#\(tag)",
              isOn: Binding(
                get: {
                  draft.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
                },
                set: { selected in
                  if selected {
                    draft.addTag(tag)
                  } else {
                    draft.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                  }
                }))
          }
        } label: {
          Label(draft.tags.isEmpty ? "Tags" : "Tags (\(draft.tags.count))", systemImage: "tag")
        }
        .fixedSize()
        .accessibilityIdentifier("dashboardTaskTagsMenu")
        TextField("New #tag", text: $draft.newTagText)
          .textFieldStyle(.roundedBorder)
          .onSubmit(addDraftTag)
          .accessibilityIdentifier("dashboardNewTagField")
        Button(action: addDraftTag) { Image(systemName: "plus") }
          .buttonStyle(PulseActionButtonStyle())
          .disabled(draft.newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityLabel("Add tag")
      }
      .font(.system(size: 12))
      .disabled(isBusy)

      if draft.card == nil {
        Text("Choose a column with a group, or create a group in Obsidian first.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let tagError {
        Text(tagError).font(.caption).foregroundStyle(.red)
      }
      if let failure = controller.addFailure {
        Text(failure.message)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("dashboardAddTaskError")
        if failure.needsReselection {
          Button("Choose file in Settings", action: onConfigure)
            .buttonStyle(PulseActionButtonStyle())
            .disabled(isBusy)
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .accessibilityIdentifier("dashboardInlineComposer")
    .onAppear { textFocused = true }
  }

  private func cardLabel(_ card: DashboardCard, in column: DashboardColumn) -> String {
    column.cards.filter { $0.title == card.title }.count > 1
      ? "\(card.title) (\(card.sourceOrder + 1))" : card.title
  }

  private func addDraftTag() {
    tagError =
      draft.addTag(draft.newTagText)
      ? nil : "Use a tag without spaces and with at least one non-numeric character."
  }

  private func submit() {
    guard !isBusy, !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }
    if !draft.newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      addDraftTag()
      guard tagError == nil else { return }
    }
    guard let request = draft.request,
      let operation = controller.addTask(request: request)
    else { return }
    Task {
      if await operation.value { presentation.didSave(request) }
    }
  }
}
