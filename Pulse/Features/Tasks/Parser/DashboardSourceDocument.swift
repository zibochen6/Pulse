import Foundation

/// Keeps byte offsets independent of Unicode graphemes and newline conventions.
struct DashboardSourceDocument: Sendable {
  struct Line: Sendable {
    let text: String
    let byteOffset: Int
  }

  let data: Data
  let lines: [Line]

  init(data: Data) throws {
    guard String(data: data, encoding: .utf8) != nil else {
      throw DashboardWriteError.unsupportedEncoding
    }
    self.data = data
    let bytes = Array(data)
    var start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
    var index = start
    var result: [Line] = []
    while index < bytes.count {
      if bytes[index] == 10 || bytes[index] == 13 {
        result.append(
          Line(text: String(decoding: bytes[start..<index], as: UTF8.self), byteOffset: start))
        if bytes[index] == 13, index + 1 < bytes.count, bytes[index + 1] == 10 { index += 1 }
        index += 1
        start = index
      } else {
        index += 1
      }
    }
    result.append(
      Line(text: String(decoding: bytes[start..<index], as: UTF8.self), byteOffset: start))
    lines = result
  }

  /// Only the verified '-' checkbox syntax; indentation is retained, never rewritten.
  static func checkbox(_ line: String) -> (
    marker: UInt8, offset: Int, indentation: Int, text: String
  )? {
    let bytes = Array(line.utf8)
    var start = 0
    var indentation = 0
    while start < bytes.count, bytes[start] == 32 || bytes[start] == 9 {
      indentation += bytes[start] == 9 ? 4 : 1
      start += 1
    }
    guard indentation % 4 == 0, bytes.count >= start + 6,
      bytes[start] == 45, bytes[start + 1] == 32, bytes[start + 2] == 91,
      bytes[start + 4] == 93, bytes[start + 5] == 32,
      bytes[start + 3] >= 32, bytes[start + 3] < 127
    else { return nil }
    return (
      bytes[start + 3], start + 3, indentation,
      String(decoding: bytes[(start + 6)...], as: UTF8.self)
    )
  }

  static func normalizedLine(_ line: String) -> String {
    guard let checkbox = checkbox(line), [32, 120, 88].contains(checkbox.marker) else {
      return line
    }
    var bytes = Array(line.utf8)
    bytes[checkbox.offset] = 32
    return String(decoding: bytes, as: UTF8.self)
  }

  /// Note cards can contain '- [[Note]]' and '- [label](url)' list items.
  /// Their opening bracket does not make them malformed checkbox tasks.
  static func isUnsupportedCheckbox(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("- ["), !trimmed.hasPrefix("- [[") else { return false }
    if let close = trimmed.firstIndex(of: "]"),
      trimmed[trimmed.index(after: close)...].hasPrefix("(")
    {
      return false
    }
    return true
  }

  func attachingSources(to dashboard: Dashboard) -> Dashboard {
    let columns = dashboard.columns.map { column in
      let cards = column.cards.map { card in
        var ancestors: [(indentation: Int, line: String)] = []
        let tasks = card.tasks.map { task -> DashboardTask in
          var task = task
          let index = task.lineNumber - 1
          guard lines.indices.contains(index), let checkbox = Self.checkbox(lines[index].text)
          else { return task }
          while let last = ancestors.last, last.indentation >= checkbox.indentation {
            ancestors.removeLast()
          }
          task.source = DashboardTaskSource(
            rawLine: lines[index].text,
            stateByteOffset: lines[index].byteOffset + checkbox.offset,
            marker: checkbox.marker,
            columnTitle: column.title,
            cardTitle: card.title,
            cardIdentifier: card.identifier,
            indentation: checkbox.indentation,
            ancestors: ancestors.map(\.line),
            previousLine: index > 0 ? Self.normalizedLine(lines[index - 1].text) : nil,
            nextLine: index + 1 < lines.count ? Self.normalizedLine(lines[index + 1].text) : nil
          )
          ancestors.append((checkbox.indentation, Self.normalizedLine(lines[index].text)))
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
      fileURL: dashboard.fileURL, columns: columns, loadedAt: dashboard.loadedAt, sourceData: data)
  }
}

/// Pure relocation logic shared by persistence and presentation reconciliation.
struct DashboardTaskLocator {
  static func normalizedData(_ dashboard: Dashboard) -> Data {
    var data = dashboard.sourceData
    for task in dashboard.allTasks {
      if let source = task.source, source.isOrdinaryCheckbox,
        data.indices.contains(source.stateByteOffset)
      {
        data[source.stateByteOffset] = 32
      }
    }
    return data
  }

  static func locate(_ task: DashboardTask, from original: Dashboard, in latest: Dashboard) throws
    -> DashboardTask
  {
    guard let source = task.source,
      task.sourceFileURL.standardizedFileURL == original.fileURL.standardizedFileURL,
      original.allTasks.contains(where: {
        $0.id == task.id && $0.source == task.source && $0.lineNumber == task.lineNumber
      })
    else { throw DashboardWriteError.conflict }
    let tasks = latest.allTasks
    // This validates the whole document, allowing only other checkbox changes.
    // It is safe even when two rows have identical text/context.
    if normalizedData(original) == normalizedData(latest) {
      guard let candidate = tasks.first(where: { $0.lineNumber == task.lineNumber }),
        matches(source, candidate.source)
      else { throw DashboardWriteError.conflict }
      return candidate
    }

    // Pulse's adjacent retry comments can become detached or move onto another
    // identical row during an external rewrite. They are not task anchors;
    // ordinary rows must pass the structural/context checks below.
    if let blockID = task.blockIdentifier {
      let originalMatches = original.allTasks.filter { $0.blockIdentifier == blockID }
      let candidates = tasks.filter { $0.blockIdentifier == blockID }
      guard originalMatches.count == 1, candidates.count == 1, let candidate = candidates.first,
        matches(source, candidate.source)
      else { throw DashboardWriteError.conflict }
      return candidate
    }

    // A card anchor must itself be unique, not its old order in the file.
    func matchingCards(in dashboard: Dashboard) -> [DashboardCard] {
      dashboard.columns.filter { $0.title == source.columnTitle }.flatMap(\.cards).filter {
        if let identifier = source.cardIdentifier {
          return $0.identifier == identifier && $0.title == source.cardTitle
        }
        return $0.title == source.cardTitle
      }
    }
    let oldCards = matchingCards(in: original)
    let newCards = matchingCards(in: latest)
    guard oldCards.count == 1, newCards.count == 1,
      let oldCard = oldCards.first, let newCard = newCards.first
    else { throw DashboardWriteError.conflict }
    let oldCandidates = oldCard.tasks.filter { matches(source, $0.source) }
    let candidates = newCard.tasks.filter { matches(source, $0.source) }
    guard oldCandidates.count == 1, candidates.count == 1, let candidate = candidates.first,
      candidate.source?.previousLine == source.previousLine,
      candidate.source?.nextLine == source.nextLine
    else { throw DashboardWriteError.conflict }
    return candidate
  }

  private static func matches(_ source: DashboardTaskSource, _ candidate: DashboardTaskSource?)
    -> Bool
  {
    guard let candidate else { return false }
    return source.columnTitle == candidate.columnTitle && source.cardTitle == candidate.cardTitle
      && source.cardIdentifier == candidate.cardIdentifier
      && source.indentation == candidate.indentation
      && source.ancestors == candidate.ancestors
      && DashboardSourceDocument.normalizedLine(source.rawLine)
        == DashboardSourceDocument.normalizedLine(candidate.rawLine)
  }
}

extension Dashboard {
  /// Reuses row identities only where source matching is proven and one-to-one.
  func preservingIdentities(from previous: Dashboard) -> Dashboard {
    guard fileURL.standardizedFileURL == previous.fileURL.standardizedFileURL else { return self }
    var identities: [Int: UUID] = [:]
    var ambiguousLines = Set<Int>()
    for oldTask in previous.allTasks {
      if let candidate = try? DashboardTaskLocator.locate(oldTask, from: previous, in: self) {
        if identities[candidate.lineNumber] != nil { ambiguousLines.insert(candidate.lineNumber) }
        identities[candidate.lineNumber] = oldTask.id
      }
    }
    let columns = columns.map { column in
      let cards = column.cards.map { card in
        let tasks = card.tasks.map { task -> DashboardTask in
          var task = task
          if !ambiguousLines.contains(task.lineNumber), let identity = identities[task.lineNumber] {
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
      fileURL: fileURL, columns: columns, loadedAt: loadedAt, sourceData: sourceData,
      observedAt: observedAt)
  }
}
