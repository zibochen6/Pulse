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
  case taskNotRepeating
  case tagMissing
  case tagConflict
  case saveFailed
  case verificationFailed
  case multipleLists
  case reservedTag
  case backupFailed

  var errorDescription: String? {
    switch self {
    case .unreadable:
      PulseLocalization.string("Pulse could not read your tasks. Check access and try again.")
    case .corruptDocument:
      PulseLocalization.string(
        "The saved tasks could not be read. The file has been kept unchanged. Restore a valid copy and retry."
      )
    case .unsupportedVersion:
      PulseLocalization.string(
        "These tasks were saved by a newer format. Update Pulse to read them; the file is unchanged."
      )
    case .multipleLists: PulseLocalization.string("Choose one list for this task.")
    case .reservedTag: PulseLocalization.string("Todo is the default list. Choose Todo instead.")
    case .backupFailed:
      PulseLocalization.string(
        "Pulse could not back up the original tasks. The original file has not been changed. Check access and retry."
      )
    case .emptyTask: PulseLocalization.string("Enter a task before saving.")
    case .emptyTag: PulseLocalization.string("Enter a tag name.")
    case .duplicateTag: PulseLocalization.string("A tag with that name already exists.")
    case .taskMissing:
      PulseLocalization.string("This task no longer exists. Refresh the list and try again.")
    case .taskConflict:
      PulseLocalization.string(
        "This task changed since it was created. Refresh before saving again.")
    case .taskNotRepeating:
      PulseLocalization.string("This task no longer repeats daily. Refresh the list and try again.")
    case .tagMissing:
      PulseLocalization.string(
        "A selected tag no longer exists. Refresh and choose the tags again.")
    case .tagConflict:
      PulseLocalization.string(
        "This list changed since it was deleted. Resolve the conflict before trying Undo again.")
    case .saveFailed:
      PulseLocalization.string("Pulse could not confirm the save. Check access and try again.")
    case .verificationFailed:
      PulseLocalization.string(
        "Pulse could not verify the saved tasks. Refresh to check the actual file.")
    }
  }
}

enum LocalTaskMutation: Sendable {
  case saveTask(
    id: UUID?, text: String, tagIDs: Set<UUID>, newTagNames: [String],
    repeatsDaily: Bool = false, creationID: UUID = UUID())
  case setCompleted(taskID: UUID, completed: Bool)
  /// Completion of a daily task for the day of `completedAt`. Idempotent within
  /// a day so reopened popovers or duplicate clicks never re-arm a task twice.
  case completeRepeating(taskID: UUID, completedAt: Date)
  /// Re-arms daily tasks finished on an earlier day. Safe to call on every
  /// popover open: when nothing is stale the store writes nothing.
  case resetRepeatingTasks(today: Date)
  case createTag(id: UUID, name: String)
  case restoreTask(LocalTaskDeletionReceipt)
  case restoreTag(LocalTagDeletionReceipt)
  case deleteTask(UUID)
  case renameTag(id: UUID, name: String)
  case deleteTag(UUID)
  /// Moves a tag to `toIndex` in the *resulting* tag array: the tag is removed
  /// first and then inserted there, so `toIndex` is the position it occupies
  /// after the move and `tags.count - 1` is "last".
  case moveTag(id: UUID, toIndex: Int)
}

/// Captured from the transaction's reread, never from a possibly stale row.
struct LocalTaskDeletionReceipt: Equatable, Identifiable, Sendable {
  let id: UUID
  let task: LocalTask
  let index: Int
  let previousID: UUID?
  let nextID: UUID?
  let deletedAt: ContinuousClock.Instant

  init(task: LocalTask, index: Int, previousID: UUID?, nextID: UUID?) {
    id = UUID()
    self.task = task
    self.index = index
    self.previousID = previousID
    self.nextID = nextID
    deletedAt = .now
  }
}

/// A whole list is one deletion, including an empty list. Positions refer to
/// the transaction's original document, before any of its targets are removed.
struct LocalTagDeletionReceipt: Equatable, Identifiable, Sendable {
  let id: UUID
  let tag: TaskTag
  let index: Int
  let previousID: UUID?
  let nextID: UUID?
  let tasks: [LocalTaskDeletionReceipt]
  let deletedAt: ContinuousClock.Instant

  init(
    tag: TaskTag, index: Int, previousID: UUID?, nextID: UUID?,
    tasks: [LocalTaskDeletionReceipt]
  ) {
    id = UUID()
    self.tag = tag
    self.index = index
    self.previousID = previousID
    self.nextID = nextID
    self.tasks = tasks
    deletedAt = .now
  }
}

enum LocalDeletionReceipt: Equatable, Identifiable, Sendable {
  case task(LocalTaskDeletionReceipt)
  case tag(LocalTagDeletionReceipt)

  var id: UUID {
    switch self {
    case .task(let receipt): receipt.id
    case .tag(let receipt): receipt.id
    }
  }

  var deletedAt: ContinuousClock.Instant {
    switch self {
    case .task(let receipt): receipt.deletedAt
    case .tag(let receipt): receipt.deletedAt
    }
  }

  var restoreMutation: LocalTaskMutation {
    switch self {
    case .task(let receipt): .restoreTask(receipt)
    case .tag(let receipt): .restoreTag(receipt)
    }
  }

  func hasSameTarget(as other: Self) -> Bool {
    switch (self, other) {
    case (.task(let first), .task(let second)): first.task.id == second.task.id
    case (.tag(let first), .tag(let second)): first.tag.id == second.tag.id
    default: false
    }
  }

  func targetIsAbsent(in document: LocalTaskDocument) -> Bool {
    switch self {
    case .task(let receipt): !document.tasks.contains { $0.id == receipt.task.id }
    case .tag(let receipt): !document.tags.contains { $0.id == receipt.tag.id }
    }
  }

  /// Changed contents alone do not establish that a deletion committed: an
  /// ordinary edit may have followed a failed write. Keep that receipt pending
  /// until a confirmed read establishes absence or the unchanged original.
  func isUnchanged(in document: LocalTaskDocument) -> Bool {
    switch self {
    case .task(let receipt):
      document.tasks.contains(receipt.task)
    case .tag(let receipt):
      document.tags.contains(receipt.tag)
        && receipt.tasks.allSatisfy { document.tasks.contains($0.task) }
    }
  }
}

/// A replacement can commit before verification fails. Carry the receipt even
/// through errors so the controller can reconcile with the actual file.
struct LocalTaskDeletionError: Error, Sendable {
  let receipt: LocalTaskDeletionReceipt
  let cause: LocalTaskStoreError
}

struct LocalTagDeletionError: Error, Sendable {
  let receipt: LocalTagDeletionReceipt
  let cause: LocalTaskStoreError
}

/// Observation order comes from the storage queue, rather than the order in
/// which asynchronous replies happen to reach the UI.
struct LocalTaskSnapshot: Sendable {
  let document: LocalTaskDocument
  let observedAt: ContinuousClock.Instant
  let deletionReceipt: LocalTaskDeletionReceipt?
  let tagDeletionReceipt: LocalTagDeletionReceipt?

  var operationDeletionReceipt: LocalDeletionReceipt? {
    if let deletionReceipt { return .task(deletionReceipt) }
    if let tagDeletionReceipt { return .tag(tagDeletionReceipt) }
    return nil
  }

  init(
    document: LocalTaskDocument, observedAt: ContinuousClock.Instant = .now,
    deletionReceipt: LocalTaskDeletionReceipt? = nil,
    tagDeletionReceipt: LocalTagDeletionReceipt? = nil
  ) {
    self.document = document
    self.deletionReceipt = deletionReceipt
    self.tagDeletionReceipt = tagDeletionReceipt
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
      let receipt: LocalTaskDeletionReceipt?
      if case .deleteTask(let id) = mutation,
        let index = original.tasks.firstIndex(where: { $0.id == id })
      {
        receipt = Self.taskReceipt(at: index, in: original.tasks)
      } else {
        receipt = nil
      }
      let tagReceipt: LocalTagDeletionReceipt?
      if case .deleteTag(let id) = mutation,
        let index = original.tags.firstIndex(where: { $0.id == id })
      {
        tagReceipt = LocalTagDeletionReceipt(
          tag: original.tags[index], index: index,
          previousID: index > 0 ? original.tags[index - 1].id : nil,
          nextID: index + 1 < original.tags.count ? original.tags[index + 1].id : nil,
          tasks: original.tasks.indices.filter { original.tasks[$0].tagIDs.contains(id) }
            .map { Self.taskReceipt(at: $0, in: original.tasks) })
      } else {
        tagReceipt = nil
      }
      var updated = original
      try Self.apply(mutation, to: &updated)
      try Self.validate(updated, singleList: true)
      guard updated != original else { return LocalTaskSnapshot(document: original) }
      do {
        try self.writeVerified(updated)
      } catch {
        if let receipt {
          throw LocalTaskDeletionError(
            receipt: receipt, cause: error as? LocalTaskStoreError ?? .saveFailed)
        }
        if let tagReceipt {
          throw LocalTagDeletionError(
            receipt: tagReceipt, cause: error as? LocalTaskStoreError ?? .saveFailed)
        }
        throw error
      }
      return LocalTaskSnapshot(
        document: updated, deletionReceipt: receipt, tagDeletionReceipt: tagReceipt)
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
    // Validate the original before compatibility work. Corrupt/newer files
    // are never normalized into a seemingly valid empty document.
    try Self.validate(document)
    let normalized = Self.normalized(document)
    if normalized != document {
      try backUpOriginal(bytes)
      try writeVerified(normalized)
    }
    return normalized
  }

  var compatibilityBackupURL: URL {
    fileURL.deletingPathExtension().appendingPathExtension("before-single-list.json")
  }

  private func backUpOriginal(_ bytes: Data) throws {
    do {
      let backup = compatibilityBackupURL
      if FileManager.default.fileExists(atPath: backup.path) {
        guard try Data(contentsOf: backup) == bytes else { throw LocalTaskStoreError.backupFailed }
      } else {
        try writer.write(bytes, to: backup)
      }
      guard try Data(contentsOf: backup) == bytes else { throw LocalTaskStoreError.backupFailed }
    } catch { throw LocalTaskStoreError.backupFailed }
  }

  private static func normalized(_ original: LocalTaskDocument) -> LocalTaskDocument {
    var result = original
    let defaultIDs = Set(original.tags.filter { canonicalName($0.name) == "todo" }.map(\.id))
    result.tags.removeAll { defaultIDs.contains($0.id) }
    for index in result.tasks.indices {
      // Choose the first ORIGINAL tag, then merge a selected Todo into default.
      let selected = original.tags.first { original.tasks[index].tagIDs.contains($0.id) }
      result.tasks[index].tagIDs =
        selected.flatMap { defaultIDs.contains($0.id) ? nil : $0.id }
        .map { Set([$0]) } ?? []
    }
    return result
  }

  private func writeVerified(_ document: LocalTaskDocument) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let bytes = try encoder.encode(document)
    do {
      let manager = FileManager.default
      if manager.fileExists(atPath: fileURL.path),
        let permissions = try manager.attributesOfItem(atPath: fileURL.path)[.posixPermissions]
          as? NSNumber,
        permissions.intValue & 0o222 == 0
      {
        throw LocalTaskStoreError.saveFailed
      }
      try manager.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try writer.write(bytes, to: fileURL)
    } catch { throw LocalTaskStoreError.saveFailed }
    guard let reread = try? Data(contentsOf: fileURL), reread == bytes,
      let verified = try? JSONDecoder().decode(LocalTaskDocument.self, from: reread),
      verified == document
    else { throw LocalTaskStoreError.verificationFailed }
  }

  private static func validate(_ document: LocalTaskDocument, singleList: Bool = false) throws {
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
          && (!singleList || $0.tagIDs.count <= 1)
      })
    else { throw LocalTaskStoreError.corruptDocument }
    // Repeating tasks deliberately add no validation: a daily task may stay
    // `completed` with or without `lastCompletedDay`, and a recorded day on a
    // task that no longer repeats is tolerated (the reset action and edits keep
    // that combination unreachable, but rejecting it would make previously
    // valid files fail to load).
  }

  /// Start of the local-calendar day containing `date`. Days are compared with
  /// `Calendar.current` because "today" is the user's wall-clock day, and the
  /// start is re-derived after each transition so daylight-saving days that are
  /// not 24 hours long still compare correctly.
  private static func dayStart(_ date: Date) -> Date {
    Calendar.current.startOfDay(for: date)
  }

  private static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
    Calendar.current.isDate(lhs, inSameDayAs: rhs)
  }

  static func canonicalName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).folding(
      options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
  }

  private static func taskReceipt(at index: Int, in tasks: [LocalTask])
    -> LocalTaskDeletionReceipt
  {
    LocalTaskDeletionReceipt(
      task: tasks[index], index: index,
      previousID: index > 0 ? tasks[index - 1].id : nil,
      nextID: index + 1 < tasks.count ? tasks[index + 1].id : nil)
  }

  private static func insertionIndex<Item: Identifiable>(
    in items: [Item], originalIndex: Int, previousID: UUID?, nextID: UUID?
  ) -> Int where Item.ID == UUID {
    if let nextID, let index = items.firstIndex(where: { $0.id == nextID }) {
      return index
    }
    if let previousID, let index = items.firstIndex(where: { $0.id == previousID }) {
      return index + 1
    }
    return max(0, min(originalIndex, items.count))
  }

  private static func apply(_ mutation: LocalTaskMutation, to document: inout LocalTaskDocument)
    throws
  {
    switch mutation {
    case .saveTask(let id, let rawText, var tagIDs, let newNames, let repeatsDaily, let creationID):
      guard tagIDs.count + newNames.count <= 1 else { throw LocalTaskStoreError.multipleLists }
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
          existing.text == text, existing.tagIDs == tagIDs.union(resolvedNewIDs),
          existing.repeatsDaily == repeatsDaily
        {
          // Edits which added new tags can be replayed after a post-write error
          // without treating those newly persisted tags as duplicate additions.
          // The repeat flag joins the comparison so replaying a draft that also
          // toggled repetition still reports an effective edit.
          return
        }
        if id == nil { throw LocalTaskStoreError.taskConflict }
      }
      // All additions are staged in this value. Invalid names leave disk untouched.
      for rawName in newNames {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LocalTaskStoreError.emptyTag }
        guard canonicalName(name) != "todo" else { throw LocalTaskStoreError.reservedTag }
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
        // Turning repetition off keeps `completed` untouched: the user's
        // finished/not-finished choice is theirs, and a stale day would make the
        // task look re-armable if repetition is turned back on. Turning it on
        // likewise leaves completion alone so the next reset handles it.
        if !repeatsDaily { document.tasks[index].lastCompletedDay = nil }
        document.tasks[index].repeatsDaily = repeatsDaily
      } else {
        document.tasks.append(
          LocalTask(id: creationID, text: text, tagIDs: tagIDs, repeatsDaily: repeatsDaily))
      }
    case .setCompleted(let id, let completed):
      guard let index = document.tasks.firstIndex(where: { $0.id == id }) else {
        throw LocalTaskStoreError.taskMissing
      }
      document.tasks[index].completed = completed
      // Un-completing drops the recorded day so a later reset cannot read a
      // manual reopen as a completion, and turning completion off never leaves
      // a repeating task looking finished for today.
      if !completed { document.tasks[index].lastCompletedDay = nil }
    case .completeRepeating(let id, let completedAt):
      guard let index = document.tasks.firstIndex(where: { $0.id == id }) else {
        throw LocalTaskStoreError.taskMissing
      }
      // Completion is only meaningful for a daily task. Throwing rather than
      // silently using `.setCompleted` semantics keeps the controller honest: it
      // only routes repeating tasks here, so reaching this is a stale UI state.
      guard document.tasks[index].repeatsDaily else {
        throw LocalTaskStoreError.taskNotRepeating
      }
      // Completing again on the same day is a no-op; a completion recorded on an
      // earlier day (or none at all) re-arms the task for today.
      if document.tasks[index].completed,
        let lastDay = document.tasks[index].lastCompletedDay,
        isSameDay(lastDay, completedAt)
      {
        return
      }
      document.tasks[index].completed = true
      document.tasks[index].lastCompletedDay = dayStart(completedAt)
    case .resetRepeatingTasks(let today):
      let todayStart = dayStart(today)
      for index in document.tasks.indices {
        guard document.tasks[index].repeatsDaily, document.tasks[index].completed else { continue }
        // A nil day means "completed, day unknown" and is treated as stale. The
        // recorded day is kept so the task still knows when it was last done.
        if let lastDay = document.tasks[index].lastCompletedDay, lastDay >= todayStart { continue }
        document.tasks[index].completed = false
      }
    case .createTag(let id, let rawName):
      let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { throw LocalTaskStoreError.emptyTag }
      guard canonicalName(name) != "todo" else { throw LocalTaskStoreError.reservedTag }
      if let existing = document.tags.first(where: { $0.id == id }) {
        guard canonicalName(existing.name) == canonicalName(name) else {
          throw LocalTaskStoreError.duplicateTag
        }
        return
      }
      guard !document.tags.contains(where: { canonicalName($0.name) == canonicalName(name) }) else {
        throw LocalTaskStoreError.duplicateTag
      }
      document.tags.append(TaskTag(id: id, name: name))
    case .restoreTask(let receipt):
      var task = receipt.task
      task.tagIDs.formIntersection(Set(document.tags.map(\.id)))
      if let existing = document.tasks.first(where: { $0.id == task.id }) {
        guard existing == task else { throw LocalTaskStoreError.taskConflict }
        return
      }
      document.tasks.insert(
        task,
        at: insertionIndex(
          in: document.tasks, originalIndex: receipt.index,
          previousID: receipt.previousID, nextID: receipt.nextID))
    case .restoreTag(let receipt):
      // Check every conflict before staging inserts. Neither an unrelated name
      // collision nor a reused task UUID may produce a partially restored list.
      if let existing = document.tags.first(where: { $0.id == receipt.tag.id }),
        existing != receipt.tag
      {
        throw LocalTaskStoreError.tagConflict
      }
      guard
        !document.tags.contains(where: {
          $0.id != receipt.tag.id && canonicalName($0.name) == canonicalName(receipt.tag.name)
        })
      else { throw LocalTaskStoreError.tagConflict }
      for taskReceipt in receipt.tasks {
        if let existing = document.tasks.first(where: { $0.id == taskReceipt.task.id }),
          existing != taskReceipt.task
        {
          throw LocalTaskStoreError.taskConflict
        }
      }
      if !document.tags.contains(where: { $0.id == receipt.tag.id }) {
        document.tags.insert(
          receipt.tag,
          at: insertionIndex(
            in: document.tags, originalIndex: receipt.index,
            previousID: receipt.previousID, nextID: receipt.nextID))
      }
      // Earlier restored targets become anchors for later contiguous targets.
      // Identical existing targets are retries and keep their current position.
      for taskReceipt in receipt.tasks.sorted(by: { $0.index < $1.index }) {
        guard !document.tasks.contains(where: { $0.id == taskReceipt.task.id }) else { continue }
        document.tasks.insert(
          taskReceipt.task,
          at: insertionIndex(
            in: document.tasks, originalIndex: taskReceipt.index,
            previousID: taskReceipt.previousID, nextID: taskReceipt.nextID))
      }
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
      guard canonicalName(name) != "todo" else { throw LocalTaskStoreError.reservedTag }
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
      document.tasks.removeAll { $0.tagIDs.contains(id) }
    case .moveTag(let id, let toIndex):
      // A tag removed while this drag was in flight is a stale request, not a
      // mistake to punish: refusing leaves the file consistent and the view
      // reconciles against the tags that actually exist.
      guard let current = document.tags.firstIndex(where: { $0.id == id }) else {
        throw LocalTaskStoreError.tagMissing
      }
      // An out-of-range destination is clamped rather than rejected. The array
      // length is the only truth here, and a drag that raced a tag deletion
      // must not turn into a hard failure over a count that drifted.
      let lastIndex = document.tags.count - 1
      let destination = max(0, min(toIndex, lastIndex))
      guard destination != current else { return }
      let moved = document.tags.remove(at: current)
      document.tags.insert(moved, at: destination)
    }
  }
}
