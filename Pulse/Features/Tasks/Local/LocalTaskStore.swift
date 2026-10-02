import Foundation

enum LocalTaskStoreError: LocalizedError, Equatable {
  case unreadable
  case corruptDocument
  case unsupportedVersion
  case emptyTask
  case emptyTag
  case duplicateTag
  case taskMissing
  case taskConflict
  case tagMissing
  case saveFailed
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .unreadable: "Pulse could not read your tasks. Check access and try again."
    case .corruptDocument:
      "The saved tasks could not be read. The file has been kept unchanged. Restore a valid copy and retry."
    case .unsupportedVersion:
      "These tasks were saved by a newer format. Update Pulse to read them; the file is unchanged."
    case .emptyTask: "Enter a task before saving."
    case .emptyTag: "Enter a tag name."
    case .duplicateTag: "A tag with that name already exists."
    case .taskMissing: "This task no longer exists. Refresh the list and try again."
    case .taskConflict: "This task changed since it was created. Refresh before saving again."
    case .tagMissing: "A selected tag no longer exists. Refresh and choose the tags again."
    case .saveFailed:
      "Pulse could not confirm the save. Check access and try again."
    case .verificationFailed:
      "Pulse could not verify the saved tasks. Refresh to check the actual file."
    }
  }
}

enum LocalTaskMutation: Sendable {
  case saveTask(
    id: UUID?, text: String, tagIDs: Set<UUID>, newTagNames: [String], creationID: UUID = UUID())
  case setCompleted(taskID: UUID, completed: Bool)
  case deleteTask(UUID)
  case renameTag(id: UUID, name: String)
  case deleteTag(UUID)
}

/// Observation order comes from the storage queue, rather than the order in
/// which asynchronous replies happen to reach the UI.
struct LocalTaskSnapshot: Sendable {
  let document: LocalTaskDocument
  let observedAt: ContinuousClock.Instant

  init(document: LocalTaskDocument, observedAt: ContinuousClock.Instant = .now) {
    self.document = document
    self.observedAt = observedAt
  }
}

protocol LocalTaskStoring: Sendable {
  func load() async throws -> LocalTaskSnapshot
  func mutate(_ mutation: LocalTaskMutation) async throws -> LocalTaskSnapshot
}

protocol LocalTaskFileWriting: Sendable {
  func write(_ data: Data, to fileURL: URL) throws
}

struct AtomicLocalTaskFileWriter: LocalTaskFileWriting {
  func write(_ data: Data, to fileURL: URL) throws {
    try data.write(to: fileURL, options: .atomic)
  }
}

/// One background queue covers all instances, including rapid operations from
/// different controllers. Every mutation rereads disk before its transaction.
final class LocalTaskStore: LocalTaskStoring, Sendable {
  private static let queue = DispatchQueue(
    label: "dev.zibochen.Pulse.local-tasks", qos: .userInitiated)
  let fileURL: URL
  private let writer: any LocalTaskFileWriting

  static var defaultFileURL: URL {
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    return support.appendingPathComponent("Pulse", isDirectory: true).appendingPathComponent(
      "tasks.json")
  }

  init(
    fileURL: URL = LocalTaskStore.defaultFileURL,
    writer: any LocalTaskFileWriting = AtomicLocalTaskFileWriter()
  ) {
    self.fileURL = fileURL
    self.writer = writer
  }

  func load() async throws -> LocalTaskSnapshot {
    try await onQueue { LocalTaskSnapshot(document: try self.readDocument()) }
  }

  func mutate(_ mutation: LocalTaskMutation) async throws -> LocalTaskSnapshot {
    try await onQueue {
      let original = try self.readDocument()
      var updated = original
      try Self.apply(mutation, to: &updated)
      try Self.validate(updated)
      guard updated != original else { return LocalTaskSnapshot(document: original) }

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let bytes = try encoder.encode(updated)
      do {
        let manager = FileManager.default
        if manager.fileExists(atPath: self.fileURL.path),
          let permissions = try manager.attributesOfItem(atPath: self.fileURL.path)[
            .posixPermissions] as? NSNumber,
          permissions.intValue & 0o222 == 0
        {
          throw LocalTaskStoreError.saveFailed
        }
        try manager.createDirectory(
          at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try self.writer.write(bytes, to: self.fileURL)
      } catch { throw LocalTaskStoreError.saveFailed }

      // Do not report an in-memory change as saved merely because write returned.
      let reread: Data
      do { reread = try Data(contentsOf: self.fileURL) } catch {
        throw LocalTaskStoreError.verificationFailed
      }
      guard reread == bytes,
        let verified = try? JSONDecoder().decode(LocalTaskDocument.self, from: reread),
        verified == updated
      else { throw LocalTaskStoreError.verificationFailed }
      return LocalTaskSnapshot(document: verified)
    }
  }

  private func onQueue<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws
    -> T
  {
    try await withCheckedThrowingContinuation { continuation in
      Self.queue.async {
        do { continuation.resume(returning: try operation()) } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func readDocument() throws -> LocalTaskDocument {
    let bytes: Data
    do { bytes = try Data(contentsOf: fileURL) } catch {
      let underlying = error as NSError
      if underlying.domain == NSCocoaErrorDomain,
        underlying.code == NSFileReadNoSuchFileError || underlying.code == NSFileNoSuchFileError
      {
        return LocalTaskDocument()
      }
      throw LocalTaskStoreError.unreadable
    }
    let document: LocalTaskDocument
    do { document = try JSONDecoder().decode(LocalTaskDocument.self, from: bytes) } catch {
      throw LocalTaskStoreError.corruptDocument
    }
    try Self.validate(document)
    return document
  }

  private static func validate(_ document: LocalTaskDocument) throws {
    guard document.schemaVersion == LocalTaskDocument.currentSchemaVersion else {
      throw LocalTaskStoreError.unsupportedVersion
    }
    let tagIDs = Set(document.tags.map(\.id))
    let names = document.tags.map { canonicalName($0.name) }
    guard tagIDs.count == document.tags.count,
      Set(names).count == names.count,
      document.tags.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      ),
      Set(document.tasks.map(\.id)).count == document.tasks.count,
      document.tasks.allSatisfy({
        !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && $0.tagIDs.isSubset(of: tagIDs)
      })
    else { throw LocalTaskStoreError.corruptDocument }
  }

  private static func canonicalName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).folding(
      options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
  }

  private static func apply(_ mutation: LocalTaskMutation, to document: inout LocalTaskDocument)
    throws
  {
    switch mutation {
    case .saveTask(let id, let rawText, var tagIDs, let newNames, let creationID):
      let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { throw LocalTaskStoreError.emptyTask }
      guard tagIDs.isSubset(of: Set(document.tags.map(\.id))) else {
        throw LocalTaskStoreError.tagMissing
      }
      // A replacement may have succeeded before verification reported failure.
      // Retrying a draft confirms that creation instead of appending a duplicate.
      if let existing = document.tasks.first(where: { $0.id == (id ?? creationID) }) {
        let resolvedNewIDs = newNames.compactMap { rawName in
          document.tags.first(where: { canonicalName($0.name) == canonicalName(rawName) })?.id
        }
        if resolvedNewIDs.count == newNames.count,
          existing.text == text, existing.tagIDs == tagIDs.union(resolvedNewIDs)
        {
          // Edits which added new tags can be replayed after a post-write error
          // without treating those newly persisted tags as duplicate additions.
          return
        }
        if id == nil { throw LocalTaskStoreError.taskConflict }
      }
      // All additions are staged in this value. Invalid names leave disk untouched.
      for rawName in newNames {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LocalTaskStoreError.emptyTag }
        guard !document.tags.contains(where: { canonicalName($0.name) == canonicalName(name) })
        else {
          throw LocalTaskStoreError.duplicateTag
        }
        let tag = TaskTag(name: name)
        document.tags.append(tag)
        tagIDs.insert(tag.id)
      }
      if let id {
        guard let index = document.tasks.firstIndex(where: { $0.id == id }) else {
          throw LocalTaskStoreError.taskMissing
        }
        document.tasks[index].text = text
        document.tasks[index].tagIDs = tagIDs
      } else {
        document.tasks.append(LocalTask(id: creationID, text: text, tagIDs: tagIDs))
      }
    case .setCompleted(let id, let completed):
      guard let index = document.tasks.firstIndex(where: { $0.id == id }) else {
        throw LocalTaskStoreError.taskMissing
      }
      document.tasks[index].completed = completed
    case .deleteTask(let id):
      guard let index = document.tasks.firstIndex(where: { $0.id == id }) else {
        return
      }
      document.tasks.remove(at: index)
    case .renameTag(let id, let rawName):
      guard let index = document.tags.firstIndex(where: { $0.id == id }) else {
        throw LocalTaskStoreError.tagMissing
      }
      let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { throw LocalTaskStoreError.emptyTag }
      guard
        !document.tags.contains(where: {
          $0.id != id && canonicalName($0.name) == canonicalName(name)
        })
      else {
        throw LocalTaskStoreError.duplicateTag
      }
      document.tags[index].name = name
    case .deleteTag(let id):
      guard let index = document.tags.firstIndex(where: { $0.id == id }) else {
        return
      }
      document.tags.remove(at: index)
      for index in document.tasks.indices { document.tasks[index].tagIDs.remove(id) }
    }
  }
}
