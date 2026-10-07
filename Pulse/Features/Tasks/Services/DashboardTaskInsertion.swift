import Foundation

/// Pure byte insertion for the existing, verified Apex card structure. This is
/// not a Markdown serializer: every existing byte is kept in its original order.
struct DashboardTaskInsertion {
  struct Patch {
    let data: Data
    let byteOffset: Int
    let byteCount: Int
  }

  static func validateOriginal(_ request: DashboardTaskCreationRequest) throws {
    let original = request.snapshot
    guard !original.sourceData.isEmpty,
      !original.allTasks.contains(where: {
        $0.pulseCreationIdentifier == request.creationIdentifier
      }),
      let column = original.columns.first(where: {
        $0.sourceOrder == request.destination.columnOrder
      }),
      let card = column.cards.first(where: { $0.sourceOrder == request.destination.cardOrder }),
      request.destination.matches(column, card)
    else { throw DashboardWriteError.conflict }
  }

  static func existingTask(for request: DashboardTaskCreationRequest, in dashboard: Dashboard)
    throws -> DashboardTask?
  {
    let text = try request.validatedText()
    let candidates = dashboard.allTasks.filter {
      $0.pulseCreationIdentifier == request.creationIdentifier
    }
    guard !candidates.isEmpty else { return nil }
    guard candidates.count == 1, let candidate = candidates.first,
      candidate.text == text, let source = candidate.source,
      source.indentation == 0, source.isOrdinaryCheckbox,
      source.columnTitle == request.destination.columnTitle,
      source.cardTitle == request.destination.cardTitle,
      source.cardIdentifier == request.destination.cardIdentifier,
      let column = dashboard.columns.first(where: { $0.title == source.columnTitle }),
      let card = column.cards.first(where: { $0.tasks.contains(where: { $0.id == candidate.id }) }),
      card.type == request.destination.cardType,
      DashboardSourceDocument.normalizedLine(source.rawLine)
        == "- [ ] \(text)"
    else { throw DashboardWriteError.conflict }
    return candidate
  }

  static func makePatch(for request: DashboardTaskCreationRequest, in latest: Dashboard) throws
    -> Patch
  {
    let text = try request.validatedText()
    let original = request.snapshot
    try validateOriginal(request)
    guard original.fileURL.standardizedFileURL == latest.fileURL.standardizedFileURL else {
      throw DashboardWriteError.conflict
    }

    let column: DashboardColumn
    let card: DashboardCard
    if DashboardTaskLocator.normalizedData(original) == DashboardTaskLocator.normalizedData(latest)
    {
      guard
        let selectedColumn = latest.columns.first(where: {
          $0.sourceOrder == request.destination.columnOrder
        }),
        let selectedCard = selectedColumn.cards.first(where: {
          $0.sourceOrder == request.destination.cardOrder
        }), request.destination.matches(selectedColumn, selectedCard)
      else { throw DashboardWriteError.conflict }
      column = selectedColumn
      card = selectedCard
    } else {
      let oldCards = original.columns.filter { $0.title == request.destination.columnTitle }
        .flatMap { selectedColumn in
          selectedColumn.cards.filter { request.destination.matches(selectedColumn, $0) }
        }
      guard oldCards.count == 1,
        let selectedColumn = latest.columns.first(where: {
          $0.title == request.destination.columnTitle
        })
      else { throw DashboardWriteError.conflict }
      let candidates = selectedColumn.cards.filter {
        request.destination.matches(selectedColumn, $0)
      }
      guard candidates.count == 1, let selectedCard = candidates.first else {
        throw DashboardWriteError.conflict
      }
      column = selectedColumn
      card = selectedCard
    }

    let document = try DashboardSourceDocument(data: latest.sourceData)
    let range = try cardLineRange(column: column, card: card, document: document)
    var insertionLine = range.upperBound
    // Keep trailing blank lines as separators, rather than consuming or moving them.
    while insertionLine > range.lowerBound + 1,
      document.lines[insertionLine - 1].text.trimmingCharacters(in: .whitespaces).isEmpty
    {
      insertionLine -= 1
    }
    let offset =
      insertionLine < document.lines.count
      ? document.lines[insertionLine].byteOffset : document.data.count
    let bytes = Array(document.data)
    let separator = newline(near: offset, bytes: bytes)
    let needsLeadingNewline = offset > 0 && bytes[offset - 1] != 10 && bytes[offset - 1] != 13
    // A file without a final newline stays without one; insertion before an
    // existing next line always needs its own separator.
    let hasFinalNewline = bytes.last == 10 || bytes.last == 13
    let trailingNewline = offset < bytes.count || hasFinalNewline ? separator : Data()
    let inserted =
      (needsLeadingNewline ? separator : Data())
      + Data("- [ ] \(text)".utf8) + separator
      + Data("<!-- pulse-task-id: \(request.creationIdentifier) -->".utf8) + trailingNewline
    var expected = document.data
    expected.insert(contentsOf: inserted, at: offset)
    return Patch(data: expected, byteOffset: offset, byteCount: inserted.count)
  }

  /// Insertion offsets are known and verified. Preserve old presentation IDs
  /// even for the adjacent last row whose neighbor necessarily changed.
  static func preservingIdentities(in verified: Dashboard, from latest: Dashboard, patch: Patch)
    -> Dashboard
  {
    let identities = Dictionary(
      uniqueKeysWithValues: latest.allTasks.compactMap { task -> (Int, UUID)? in
        guard let source = task.source else { return nil }
        let offset = source.stateByteOffset
        return (offset >= patch.byteOffset ? offset + patch.byteCount : offset, task.id)
      })
    let columns = verified.columns.map { column in
      let cards = column.cards.map { card in
        let tasks = card.tasks.map { task -> DashboardTask in
          var task = task
          if let offset = task.source?.stateByteOffset, let identity = identities[offset] {
            task.presentationID = identity
          }
          return task
        }
        return DashboardCard(
          identifier: card.identifier, title: card.title, type: card.type, tasks: tasks,
          sourceOrder: card.sourceOrder)
      }
      return DashboardColumn(
        title: column.title, color: column.color, type: column.type, cards: cards,
        sourceOrder: column.sourceOrder)
    }
    return Dashboard(
      fileURL: verified.fileURL, columns: columns, loadedAt: verified.loadedAt,
      sourceData: verified.sourceData, observedAt: verified.observedAt)
  }

  private static func cardLineRange(
    column: DashboardColumn, card: DashboardCard, document: DashboardSourceDocument
  ) throws -> Range<Int> {
    var currentColumn: String?
    var cardOrder = -1
    var start: Int?
    var fence: (character: Character, count: Int)?
    // Headings inside fenced examples are not destinations.
    guard let frontmatterEnd = document.lines.dropFirst().firstIndex(where: { $0.text == "---" })
    else { throw DashboardWriteError.conflict }
    for (index, line) in document.lines.enumerated().dropFirst(frontmatterEnd + 1) {
      let trimmed = line.text.trimmingCharacters(in: .whitespaces)
      if let active = fence {
        let count = trimmed.prefix(while: { $0 == active.character }).count
        if count >= active.count,
          trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty
        {
          fence = nil
        }
        continue
      }
      if let first = trimmed.first, first == "`" || first == "~" {
        let count = trimmed.prefix(while: { $0 == first }).count
        if count >= 3 {
          fence = (first, count)
          continue
        }
      }
      if line.text.hasPrefix("## ") || line.text.hasPrefix("### ") {
        if let start { return start..<index }
        if line.text.hasPrefix("## ") {
          currentColumn = String(line.text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
          cardOrder = -1
        } else {
          cardOrder += 1
          if currentColumn == column.title, cardOrder == card.sourceOrder { start = index }
        }
      }
    }
    guard let start else { throw DashboardWriteError.conflict }
    return start..<document.lines.count
  }

  private static func newline(near offset: Int, bytes: [UInt8]) -> Data {
    if offset > 0 {
      for index in stride(from: min(offset - 1, bytes.count - 1), through: 0, by: -1) {
        if bytes[index] == 10 {
          return index > 0 && bytes[index - 1] == 13 ? Data([13, 10]) : Data([10])
        }
        if bytes[index] == 13 { return Data([13]) }
      }
    }
    return Data([10])
  }
}
