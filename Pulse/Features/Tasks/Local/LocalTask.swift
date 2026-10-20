import Foundation

/// The app's own to-dos: plain local JSON rows with tags, completion and an
/// optional daily repeat. Nothing here is imported from or written back to a file.
struct LocalTask: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  var text: String
  var completed: Bool
  var tagIDs: Set<UUID>
  /// A repeating task is re-armed for a new day by `LocalTaskMutation.resetRepeatingTasks`.
  var repeatsDaily: Bool
  /// Local-calendar day (start of that day) on which a repeating task was last
  /// completed. Stored as a day rather than an instant so "already completed
  /// today" survives daylight-saving shifts and time-zone travel that would
  /// otherwise make the same wall-clock moment fall on a different day.
  var lastCompletedDay: Date?

  init(
    id: UUID = UUID(), text: String, completed: Bool = false, tagIDs: Set<UUID> = [],
    repeatsDaily: Bool = false, lastCompletedDay: Date? = nil
  ) {
    self.id = id
    self.text = text
    self.completed = completed
    self.tagIDs = tagIDs
    self.repeatsDaily = repeatsDaily
    self.lastCompletedDay = lastCompletedDay
  }

  private enum CodingKeys: String, CodingKey {
    case id, text, completed, tagIDs, repeatsDaily, lastCompletedDay
  }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    text = try values.decode(String.self, forKey: .text)
    completed = try values.decode(Bool.self, forKey: .completed)
    tagIDs = Set(try values.decode([UUID].self, forKey: .tagIDs))
    // Optional decoding keeps schema version 1 files written before repeating
    // tasks existed readable, so no migration is required.
    repeatsDaily = try values.decodeIfPresent(Bool.self, forKey: .repeatsDaily) ?? false
    // Decode the same fixed ISO8601 string the encoder writes, so a written
    // document verifies byte-for-byte when it is read back.
    lastCompletedDay = try values.decodeIfPresent(String.self, forKey: .lastCompletedDay)
      .flatMap(LocalTaskDateCoding.date(from:))
  }

  func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(text, forKey: .text)
    try values.encode(completed, forKey: .completed)
    // Stable output makes changes inspectable without random Set ordering.
    try values.encode(tagIDs.sorted { $0.uuidString < $1.uuidString }, forKey: .tagIDs)
    // Always written so a file states its repeat intent explicitly; the key
    // stays optional on decode to preserve the older format.
    try values.encode(repeatsDaily, forKey: .repeatsDaily)
    // Written only when set, in a fixed UTC whole-second form: two equal
    // documents must serialize to identical bytes for the store's write
    // verification, which compares the reread bytes with what it wrote.
    if let lastCompletedDay {
      try values.encode(
        LocalTaskDateCoding.string(from: lastCompletedDay), forKey: .lastCompletedDay)
    }
  }
}

/// The single wire format for persisted task days. Whole seconds in UTC keep
/// output independent of locale, calendar and sub-second clock noise; a
/// non-UTC or fractional format would make equal documents encode differently
/// and fail the store's byte-for-byte write verification.
enum LocalTaskDateCoding {
  static func string(from date: Date) -> String {
    LocalTaskDateFormatter.make().string(
      from: Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)))
  }

  static func date(from string: String) -> Date? {
    LocalTaskDateFormatter.make().date(from: string)
  }
}

/// `ISO8601DateFormatter` is a reference type and not `Sendable`, while the
/// store encodes on its background queue. Building a short-lived instance per
/// call keeps the format fixed without sharing mutable state across threads.
private enum LocalTaskDateFormatter {
  static func make() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
  }
}

struct TaskTag: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  var name: String

  init(id: UUID = UUID(), name: String) {
    self.id = id
    self.name = name
  }
}

struct LocalTaskDocument: Codable, Equatable, Sendable {
  // Repeating-task keys are optional, so documents written by this build stay
  // readable by schema version 1 readers and vice versa. Bumping the version
  // would strand existing files behind `unsupportedVersion`.
  static let currentSchemaVersion = 1
  var schemaVersion: Int
  var tasks: [LocalTask]
  var tags: [TaskTag]

  init(
    schemaVersion: Int = Self.currentSchemaVersion, tasks: [LocalTask] = [], tags: [TaskTag] = []
  ) {
    self.schemaVersion = schemaVersion
    self.tasks = tasks
    self.tags = tags
  }
}

enum LocalTaskFilter: Equatable, Hashable, Sendable {
  case all
  case untagged
  case tag(UUID)
}
