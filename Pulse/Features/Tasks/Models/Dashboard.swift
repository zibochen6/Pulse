import Foundation

struct Dashboard: Equatable, Sendable {
  let fileURL: URL
  let columns: [DashboardColumn]
  let loadedAt: Date
}

struct DashboardColumn: Equatable, Sendable, Identifiable {
  let title: String
  let color: String
  let type: String
  let cards: [DashboardCard]
  let sourceOrder: Int

  var id: Int { sourceOrder }
}

struct DashboardCard: Equatable, Sendable, Identifiable {
  let identifier: String?
  let title: String
  let type: String?
  let tasks: [DashboardTask]
  let sourceOrder: Int

  var id: String { identifier ?? "card-\(sourceOrder)" }
}

struct DashboardTask: Equatable, Sendable, Identifiable {
  let text: String
  let completed: Bool
  let sourceFileURL: URL
  let lineNumber: Int
  let blockIdentifier: String?
  let sourceOrder: Int

  var id: String { blockIdentifier ?? "task-\(lineNumber)-\(sourceOrder)" }
}
