import Foundation

/// Selects one existing card, without assigning a meaning to its column title.
struct DashboardTaskDestination: Equatable, Sendable {
  let columnTitle: String
  let columnOrder: Int
  let cardTitle: String
  let cardIdentifier: String?
  let cardType: String?
  let cardOrder: Int

  init(column: DashboardColumn, card: DashboardCard) {
    columnTitle = column.title
    columnOrder = column.sourceOrder
    cardTitle = card.title
    cardIdentifier = card.identifier
    cardType = card.type
    cardOrder = card.sourceOrder
  }

  func matches(_ column: DashboardColumn, _ card: DashboardCard) -> Bool {
    column.title == columnTitle && card.title == cardTitle
      && card.identifier == cardIdentifier && card.type == cardType
  }
}

/// Keep the ID and original snapshot when retrying an uncertain save. The
/// creation identifier is persisted separately from the checkbox task text.
struct DashboardTaskCreationRequest: Equatable, Sendable {
  let id: UUID
  let text: String
  let destination: DashboardTaskDestination
  let snapshot: Dashboard

  init(
    id: UUID = UUID(), text: String, destination: DashboardTaskDestination, snapshot: Dashboard
  ) {
    self.id = id
    self.text = text
    self.destination = destination
    self.snapshot = snapshot
  }

  var creationIdentifier: String { "pulse-" + id.uuidString.lowercased() }

  func validatedText() throws -> String {
    let value = text.trimmingCharacters(in: .whitespaces)
    guard !value.isEmpty,
      !value.unicodeScalars.contains(where: {
        // Emoji can contain Unicode format scalars such as zero-width joiners.
        // Reject line breaks/ASCII controls, rather than rejecting valid emoji.
        $0.value < 32 || $0.value == 127 || CharacterSet.newlines.contains($0)
      })
    else { throw DashboardWriteError.invalidTaskText }
    return value
  }
}
