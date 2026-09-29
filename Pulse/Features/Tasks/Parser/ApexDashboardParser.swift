import Foundation

enum DashboardParseError: LocalizedError, Equatable, Sendable {
  case missingFrontmatter
  case invalidFrontmatter(String)
  case missingColumns
  case unsupportedFrontmatter(String)
  case undeclaredColumn(String)
  case missingColumnHeading(String)
  case cardOutsideColumn(line: Int)
  case taskOutsideCard(line: Int)
  case unsupportedTaskStructure(line: Int)
  case emptyTask(line: Int)

  var errorDescription: String? {
    switch self {
    case .missingFrontmatter:
      "The file does not contain Apex Dashboard frontmatter."
    case .invalidFrontmatter(let detail):
      "The Apex Dashboard frontmatter is invalid: \(detail)"
    case .missingColumns:
      "The Apex Dashboard does not declare any columns."
    case .unsupportedFrontmatter(let detail):
      "The Apex Dashboard uses unsupported frontmatter: \(detail)"
    case .undeclaredColumn(let title):
      "The column \"\(title)\" is not declared in the Dashboard frontmatter."
    case .missingColumnHeading(let title):
      "The declared column \"\(title)\" does not have a matching heading."
    case .cardOutsideColumn(let line):
      "A card appears before a column heading on line \(line)."
    case .taskOutsideCard(let line):
      "A task appears outside a card on line \(line)."
    case .unsupportedTaskStructure(let line):
      "The task structure on line \(line) is not supported by Apex read-only view."
    case .emptyTask(let line):
      "The task on line \(line) has no text."
    }
  }
}

/// Parses only the Apex Dashboard structure verified by Pulse's research.
struct ApexDashboardParser: Sendable {
  func parse(contents: String, fileURL: URL, loadedAt: Date = Date()) throws -> Dashboard {
    let lines = contents.components(separatedBy: .newlines)
    let frontmatterEnd = try frontmatterEnd(in: lines)
    let declarations = try parseDeclarations(Array(lines[1..<frontmatterEnd]))
    let columns = try parseBody(
      Array(lines.dropFirst(frontmatterEnd + 1)),
      lineOffset: frontmatterEnd + 1,
      declarations: declarations,
      fileURL: fileURL
    )
    return Dashboard(fileURL: fileURL, columns: columns, loadedAt: loadedAt)
  }

  private func frontmatterEnd(in lines: [String]) throws -> Int {
    guard lines.first == "---" else { throw DashboardParseError.missingFrontmatter }
    guard let end = lines.dropFirst().firstIndex(of: "---") else {
      throw DashboardParseError.invalidFrontmatter("missing closing delimiter")
    }
    return end
  }

  private func parseDeclarations(_ lines: [String]) throws -> [ColumnDeclaration] {
    var dashboardIsEnabled = false
    var columnsStart: Int?
    for (index, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed == "dashboard: true" { dashboardIsEnabled = true }
      if trimmed == "columns:" { columnsStart = index }
    }
    guard dashboardIsEnabled else {
      throw DashboardParseError.invalidFrontmatter("dashboard: true is required")
    }
    guard let columnsStart else { throw DashboardParseError.missingColumns }

    var declarations: [ColumnDeclaration] = []
    var current: ColumnDeclaration?
    for line in lines.dropFirst(columnsStart + 1) {
      if line.hasPrefix("  - name: ") {
        if let current { declarations.append(current) }
        let name = String(line.dropFirst("  - name: ".count)).trimmingCharacters(in: .whitespaces)
        guard isSimpleValue(name) else {
          throw DashboardParseError.unsupportedFrontmatter("column names must be plain values")
        }
        current = ColumnDeclaration(name: name, color: nil, type: nil)
      } else if line.hasPrefix("    color: ") {
        guard var declaration = current else {
          throw DashboardParseError.invalidFrontmatter("color without a column")
        }
        declaration.color = try frontmatterValue(line, prefix: "    color: ", field: "color")
        current = declaration
      } else if line.hasPrefix("    type: ") {
        guard var declaration = current else {
          throw DashboardParseError.invalidFrontmatter("type without a column")
        }
        declaration.type = try frontmatterValue(line, prefix: "    type: ", field: "type")
        current = declaration
      } else if line.hasPrefix("    ") || line.hasPrefix("  - ") {
        throw DashboardParseError.unsupportedFrontmatter("only name, color, and type are supported for columns")
      } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
        // The known `banner` block precedes columns. A top-level field after
        // columns would make the simple reader ambiguous, so reject it.
        throw DashboardParseError.unsupportedFrontmatter("unexpected field after columns")
      }
    }
    if let current { declarations.append(current) }
    guard !declarations.isEmpty else { throw DashboardParseError.missingColumns }
    for declaration in declarations {
      guard let color = declaration.color, let type = declaration.type,
        isSimpleValue(color), isSimpleValue(type)
      else {
        throw DashboardParseError.invalidFrontmatter("every column needs color and type")
      }
    }
    let names = declarations.map(\.name)
    guard Set(names).count == names.count else {
      throw DashboardParseError.invalidFrontmatter("column names must be unique")
    }
    return declarations
  }

  private func frontmatterValue(_ line: String, prefix: String, field: String) throws -> String {
    let raw = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    let value: String
    if raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2 {
      value = String(raw.dropFirst().dropLast())
    } else {
      value = raw
    }
    guard isSimpleValue(value) else {
      throw DashboardParseError.unsupportedFrontmatter("\(field) must be a simple value")
    }
    return value
  }

  private func isSimpleValue(_ value: String) -> Bool {
    !value.isEmpty && !value.contains(":") && !value.contains("[") && !value.contains("{")
  }

  private func parseBody(
    _ lines: [String], lineOffset: Int, declarations: [ColumnDeclaration], fileURL: URL
  ) throws -> [DashboardColumn] {
    var cardsByColumn = Dictionary(uniqueKeysWithValues: declarations.map { ($0.name, [DashboardCard]()) })
    let declaredOrder = declarations.map(\.name)
    var seenColumns = Set<String>()
    var currentColumn: String?
    var currentCard: MutableCard?
    var taskOrder = 0

    func finishCard() {
      guard let currentCard, let column = currentColumn else { return }
      cardsByColumn[column, default: []].append(currentCard.value)
    }

    for (offset, line) in lines.enumerated() {
      let lineNumber = lineOffset + offset + 1
      if line.hasPrefix("## ") {
        finishCard()
        currentCard = nil
        let title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        guard declarations.contains(where: { $0.name == title }) else {
          throw DashboardParseError.undeclaredColumn(title)
        }
        guard !seenColumns.contains(title) else {
          throw DashboardParseError.invalidFrontmatter("column heading \"\(title)\" appears more than once")
        }
        seenColumns.insert(title)
        currentColumn = title
      } else if line.hasPrefix("### ") {
        guard let column = currentColumn else { throw DashboardParseError.cardOutsideColumn(line: lineNumber) }
        finishCard()
        currentCard = MutableCard(
          title: String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces),
          sourceOrder: cardsByColumn[column, default: []].count
        )
      } else if let checkbox = checkbox(in: line) {
        guard currentColumn != nil else { throw DashboardParseError.taskOutsideCard(line: lineNumber) }
        guard var card = currentCard else { throw DashboardParseError.taskOutsideCard(line: lineNumber) }
        let parsed = try taskTextAndBlockIdentifier(checkbox.text, line: lineNumber)
        card.tasks.append(
          DashboardTask(
            text: parsed.text,
            completed: checkbox.completed,
            sourceFileURL: fileURL,
            lineNumber: lineNumber,
            blockIdentifier: parsed.blockIdentifier,
            sourceOrder: taskOrder
          )
        )
        taskOrder += 1
        currentCard = card
      } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("- [") {
        throw DashboardParseError.unsupportedTaskStructure(line: lineNumber)
      } else if line.hasPrefix("#") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
        throw DashboardParseError.unsupportedTaskStructure(line: lineNumber)
      } else if var card = currentCard, let metadata = cardMetadata(in: line) {
        switch metadata.key {
        case "id": card.identifier = metadata.value
        case "type": card.type = metadata.value
        default: break
        }
        currentCard = card
      }
    }
    finishCard()

    for name in declaredOrder where !seenColumns.contains(name) {
      throw DashboardParseError.missingColumnHeading(name)
    }
    var columns: [DashboardColumn] = []
    for (index, declaration) in declarations.enumerated() {
      guard let color = declaration.color, let type = declaration.type else {
        throw DashboardParseError.invalidFrontmatter("every column needs color and type")
      }
      columns.append(
        DashboardColumn(
          title: declaration.name,
          color: color,
          type: type,
          cards: cardsByColumn[declaration.name, default: []],
          sourceOrder: index
        )
      )
    }
    return columns
  }

  private func checkbox(in line: String) -> (completed: Bool, text: String)? {
    if line.hasPrefix("- [ ] ") { return (false, String(line.dropFirst(6))) }
    if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
      return (true, String(line.dropFirst(6)))
    }
    return nil
  }

  private func taskTextAndBlockIdentifier(_ raw: String, line: Int) throws -> (text: String, blockIdentifier: String?) {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { throw DashboardParseError.emptyTask(line: line) }
    guard let marker = trimmed.range(of: " ^", options: .backwards) else { return (trimmed, nil) }
    let text = String(trimmed[..<marker.lowerBound]).trimmingCharacters(in: .whitespaces)
    let identifier = String(trimmed[marker.upperBound...])
    guard !text.isEmpty, !identifier.isEmpty,
      identifier.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    else { return (trimmed, nil) }
    return (text, identifier)
  }

  private func cardMetadata(in line: String) -> (key: String, value: String)? {
    guard !line.hasPrefix(" "), let separator = line.firstIndex(of: ":") else { return nil }
    let key = String(line[..<separator])
    guard key == "id" || key == "type" else { return nil }
    let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
    return value.isEmpty ? nil : (key, value)
  }
}

private struct ColumnDeclaration {
  let name: String
  var color: String?
  var type: String?
}

private struct MutableCard {
  var identifier: String?
  let title: String
  var type: String?
  var tasks: [DashboardTask] = []
  let sourceOrder: Int

  var value: DashboardCard {
    DashboardCard(identifier: identifier, title: title, type: type, tasks: tasks, sourceOrder: sourceOrder)
  }
}
