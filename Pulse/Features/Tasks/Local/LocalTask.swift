import Foundation

/// Built-in tasks are independent from a Dashboard's file-backed source locators.
struct LocalTask: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  var text: String
  var completed: Bool
  var tagIDs: Set<UUID>

  init(id: UUID = UUID(), text: String, completed: Bool = false, tagIDs: Set<UUID> = []) {
    self.id = id
    self.text = text
    self.completed = completed
    self.tagIDs = tagIDs
  }

  private enum CodingKeys: String, CodingKey { case id, text, completed, tagIDs }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    text = try values.decode(String.self, forKey: .text)
    completed = try values.decode(Bool.self, forKey: .completed)
    tagIDs = Set(try values.decode([UUID].self, forKey: .tagIDs))
  }

  func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(text, forKey: .text)
    try values.encode(completed, forKey: .completed)
    // Stable output makes changes inspectable without random Set ordering.
    try values.encode(tagIDs.sorted { $0.uuidString < $1.uuidString }, forKey: .tagIDs)
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
