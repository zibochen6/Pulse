import AppKit
import Combine
import Foundation

struct QuickCopyEntry: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  var name: String
  var text: String

  static func == (lhs: QuickCopyEntry, rhs: QuickCopyEntry) -> Bool {
    // Swift String equality is canonical. The shelf preserves the exact text
    // even when an edit only changes a character's Unicode representation.
    lhs.id == rhs.id && lhs.name.utf8.elementsEqual(rhs.name.utf8)
      && lhs.text.utf8.elementsEqual(rhs.text.utf8)
  }
}

@MainActor
final class QuickCopyController: ObservableObject {
  enum Issue: Equatable {
    case load
    case save
    case delete(UUID)
    case copy(UUID)

    var message: String {
      switch self {
      case .load: PulseLocalization.string("Couldn't load saved entries.")
      case .save: PulseLocalization.string("Couldn't save the entry.")
      case .delete: PulseLocalization.string("Couldn't delete the entry.")
      case .copy: PulseLocalization.string("Couldn't copy the text.")
      }
    }
  }

  @Published private var document: [QuickCopyEntry]?
  @Published private(set) var isLoading = false
  @Published private(set) var hasPendingWrite = false
  @Published private(set) var draft: QuickCopyEntry?
  @Published private(set) var issue: Issue?
  @Published private(set) var copiedEntryID: UUID?

  private let store: QuickCopyStore
  private let writeToClipboard: (String) -> Bool
  private var copyFeedbackTask: Task<Void, Never>?

  init(fileURL: URL, writeToClipboard: @escaping (String) -> Bool) {
    store = QuickCopyStore(fileURL: fileURL)
    self.writeToClipboard = writeToClipboard
  }

  var hasLoaded: Bool { document != nil }
  var entries: [QuickCopyEntry] { document ?? [] }

  var hasUnsavedEdits: Bool {
    guard let draft else { return false }
    if let saved = entries.first(where: { $0.id == draft.id }) { return draft != saved }
    return !draft.name.isEmpty || !draft.text.isEmpty
  }

  var isEditingSavedEntry: Bool {
    guard let draft else { return false }
    return entries.contains { $0.id == draft.id }
  }

  var canSaveDraft: Bool {
    guard let draft, !hasPendingWrite else { return false }
    return !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !draft.text.isEmpty
  }

  func filteredEntries(matching search: String) -> [QuickCopyEntry] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty ? entries : entries.filter { $0.name.localizedStandardContains(query) }
  }

  func loadIfNeeded() async {
    guard !hasLoaded, !isLoading else { return }
    issue = nil
    isLoading = true
    defer { isLoading = false }
    do {
      document = try await store.load()
    } catch {
      issue = .load
    }
  }

  func beginAdding() {
    guard hasLoaded, !hasPendingWrite, draft == nil else { return }
    clearCopyFeedback()
    issue = nil
    draft = QuickCopyEntry(id: UUID(), name: "", text: "")
  }

  func beginEditing(_ id: UUID) {
    guard !hasPendingWrite, draft == nil, let entry = entries.first(where: { $0.id == id }) else {
      return
    }
    clearCopyFeedback()
    issue = nil
    draft = entry
  }

  func setDraftName(_ name: String, for id: UUID) {
    guard !hasPendingWrite, draft?.id == id else { return }
    draft?.name = name
  }

  func setDraftText(_ text: String, for id: UUID) {
    guard !hasPendingWrite, draft?.id == id else { return }
    draft?.text = text
  }

  func discardDraft() {
    guard !hasPendingWrite, draft != nil else { return }
    draft = nil
    issue = nil
  }

  @discardableResult
  func saveDraft() async -> Bool {
    guard canSaveDraft, var entry = draft else { return false }
    entry.name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
    var updated = entries
    if let index = updated.firstIndex(where: { $0.id == entry.id }) {
      updated[index] = entry
    } else {
      updated.append(entry)
    }
    return await persist(updated, failure: .save) { draft = nil }
  }

  @discardableResult
  func deleteEntry(_ id: UUID) async -> Bool {
    guard !hasPendingWrite, draft == nil, let index = entries.firstIndex(where: { $0.id == id })
    else { return false }
    var updated = entries
    updated.remove(at: index)
    return await persist(updated, failure: .delete(id)) {
      if copiedEntryID == id { clearCopyFeedback() }
    }
  }

  func dismissIssue() {
    issue = nil
  }

  @discardableResult
  func copy(_ id: UUID) -> Bool {
    guard let entry = entries.first(where: { $0.id == id }) else { return false }
    copyFeedbackTask?.cancel()
    guard writeToClipboard(entry.text) else {
      clearCopyFeedback()
      issue = .copy(id)
      return false
    }
    if case .copy = issue { issue = nil }
    if copiedEntryID != id { copiedEntryID = id }
    copyFeedbackTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(1_400))
        try Task.checkCancellation()
        self?.clearCopyFeedback()
      } catch {
        // A later copy or leaving the page cancels this expiry.
      }
    }
    return true
  }

  func clearCopyFeedback() {
    copyFeedbackTask?.cancel()
    copyFeedbackTask = nil
    if copiedEntryID != nil { copiedEntryID = nil }
  }

  static func write(_ text: String, to pasteboard: NSPasteboard) -> Bool {
    let item = NSPasteboardItem()
    guard item.setString(text, forType: .string) else { return false }
    pasteboard.clearContents()
    return pasteboard.writeObjects([item])
  }

  private func persist(
    _ updated: [QuickCopyEntry], failure: Issue, didWrite: () -> Void
  ) async -> Bool {
    hasPendingWrite = true
    issue = nil
    defer { hasPendingWrite = false }
    do {
      try await store.save(updated)
      document = updated
      didWrite()
      return true
    } catch {
      issue = failure
      return false
    }
  }
}

private actor QuickCopyStore {
  private struct Document: Codable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let entries: [QuickCopyEntry]
  }

  private enum DocumentError: Error {
    case unsupportedVersion
    case duplicateID
  }

  let fileURL: URL

  init(fileURL: URL) { self.fileURL = fileURL }

  func load() throws -> [QuickCopyEntry] {
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return []
    }
    let document = try JSONDecoder().decode(Document.self, from: data)
    guard document.schemaVersion == Document.currentSchemaVersion else {
      throw DocumentError.unsupportedVersion
    }
    guard Set(document.entries.map(\.id)).count == document.entries.count else {
      throw DocumentError.duplicateID
    }
    return document.entries
  }

  func save(_ entries: [QuickCopyEntry]) throws {
    let document = Document(schemaVersion: Document.currentSchemaVersion, entries: entries)
    let data = try JSONEncoder().encode(document)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: fileURL, options: .atomic)
  }
}
