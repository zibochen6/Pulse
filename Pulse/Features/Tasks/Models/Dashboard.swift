import Foundation

struct Dashboard: Equatable, Sendable {
  let fileURL: URL
  let columns: [DashboardColumn]
  let loadedAt: Date
  /// Original bytes are an in-memory revision, never a persisted task cache.
  var sourceData = Data()
  /// Set on the serial file worker; orders actual observations, not task scheduling.
  var observedAt: ContinuousClock.Instant?

  var allTasks: [DashboardTask] { columns.flatMap { $0.cards.flatMap(\.tasks) } }
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

  var id: Int { sourceOrder }
}

struct DashboardTask: Equatable, Sendable, Identifiable {
  let text: String
  let completed: Bool
  let sourceFileURL: URL
  let lineNumber: Int
  let blockIdentifier: String?
  let sourceOrder: Int
  var presentationID = UUID()
  var source: DashboardTaskSource?

  var id: UUID { presentationID }
  var canToggle: Bool { source?.isOrdinaryCheckbox == true }
}

/// A file locator, deliberately separate from the identity used by SwiftUI.
struct DashboardTaskSource: Equatable, Sendable {
  let rawLine: String
  let stateByteOffset: Int
  let marker: UInt8
  let columnTitle: String
  let cardTitle: String
  let cardIdentifier: String?
  let indentation: Int
  let ancestors: [String]
  let previousLine: String?
  let nextLine: String?

  var isOrdinaryCheckbox: Bool { marker == 32 || marker == 120 || marker == 88 }
}
