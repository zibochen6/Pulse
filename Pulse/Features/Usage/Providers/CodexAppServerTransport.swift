import Darwin
import Foundation

struct CodexAppServerTransport: CodexAppServerReading {
  func readRateLimits() async throws -> Data {
    // Process and pipe reads are blocking; keep them off the AppKit main actor.
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        do {
          continuation.resume(returning: try Self.run())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func run() throws -> Data {
    let binary = try CodexBinaryLocator.resolveForLaunch()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["app-server", "--listen", "stdio://"]
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    // stderr can contain account details. Discard it rather than logging it.
    process.standardError = FileHandle.nullDevice

    do { try process.run() } catch { throw CodexUsageError.launchFailed }
    defer {
      try? input.fileHandleForWriting.close()
      try? output.fileHandleForReading.close()
      if process.isRunning {
        process.terminate()
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
      }
      process.waitUntilExit()
    }

    var reader = JSONLineReader(fileDescriptor: output.fileHandleForReading.fileDescriptor)
    let deadline = DispatchTime.now().uptimeNanoseconds + 10_000_000_000

    try write(
      #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"pulse","title":"Pulse","version":"0.2"},"capabilities":{"experimentalApi":true}}}"#,
      to: input)
    let handshake = try reader.response(id: 1, deadline: deadline)
    if handshake["error"] != nil { throw CodexUsageError.serverRejected }
    guard handshake["result"] != nil else { throw CodexUsageError.invalidResponse }

    try write(#"{"method":"initialized"}"#, to: input)
    try write(#"{"method":"account/rateLimits/read","id":2}"#, to: input)
    return try reader.responseData(id: 2, deadline: deadline)
  }

  private static func write(_ line: String, to pipe: Pipe) throws {
    do {
      try pipe.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
    } catch {
      throw CodexUsageError.serverExited
    }
  }
}

enum CodexBinaryLocator {
  static func resolveForLaunch(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: String = NSHomeDirectory(),
    fileManager: FileManager = .default
  ) throws -> String {
    if let binary = resolve(environment: environment, home: home, fileManager: fileManager) {
      return binary
    }
    if let override = environment["CODEX_BIN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !override.isEmpty
    {
      throw CodexUsageError.invalidBinaryOverride
    }
    throw CodexUsageError.binaryNotFound
  }

  static func resolve(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: String = NSHomeDirectory(),
    fileManager: FileManager = .default
  ) -> String? {
    candidates(environment: environment, home: home)
      .first(where: { fileManager.isExecutableFile(atPath: $0) })
  }

  static func candidates(environment: [String: String], home: String) -> [String] {
    if let override = environment["CODEX_BIN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !override.isEmpty
    {
      return [(override as NSString).expandingTildeInPath]
    }
    let appRoots = [
      "/Applications/ChatGPT.app", "\(home)/Applications/ChatGPT.app",
      "/Applications/Codex.app", "\(home)/Applications/Codex.app",
    ]
    var paths: [String] = []
    for root in appRoots {
      let cliRoot = "\(root)/Contents/Resources/codex-cli"
      if let entrypoint = packageEntrypoint(at: "\(cliRoot)/codex-package.json") {
        paths.append("\(cliRoot)/\(entrypoint)")
      }
      paths.append("\(cliRoot)/CodexCLI.app/Contents/MacOS/codex")
      paths.append("\(cliRoot)/bin/codex")
      paths.append("\(root)/Contents/Resources/codex")
    }
    paths += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex"]
    for directory in (environment["PATH"] ?? "").split(separator: ":") {
      paths.append("\(directory)/codex")
    }
    var seen = Set<String>()
    return paths.map { ($0 as NSString).standardizingPath }.filter { seen.insert($0).inserted }
  }

  private static func packageEntrypoint(at path: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path),
      let package = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let entrypoint = package["entrypoint"] as? String,
      !entrypoint.isEmpty,
      !entrypoint.hasPrefix("/"),
      !entrypoint.split(separator: "/").contains("..")
    else { return nil }
    return entrypoint
  }
}

/// Reads complete newline-delimited messages and correlates response IDs.
private struct JSONLineReader {
  let fileDescriptor: Int32
  private var pending = Data()

  init(fileDescriptor: Int32) {
    self.fileDescriptor = fileDescriptor
  }

  mutating func response(id: Int, deadline: UInt64) throws -> [String: Any] {
    let data = try responseData(id: id, deadline: deadline)
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw CodexUsageError.invalidResponse }
    return object
  }

  mutating func responseData(id: Int, deadline: UInt64) throws -> Data {
    while true {
      while let newline = pending.firstIndex(of: 10) {
        let line = Data(pending[..<newline])
        pending.removeSubrange(...newline)
        guard !line.isEmpty else { continue }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { throw CodexUsageError.invalidResponse }
        let responseID =
          (object["id"] as? NSNumber)?.intValue
          ?? (object["id"] as? String).flatMap(Int.init)
        if responseID == id { return line }
      }

      let now = DispatchTime.now().uptimeNanoseconds
      guard now < deadline else { throw CodexUsageError.timeout }
      let remaining = Int32(min((deadline - now) / 1_000_000, UInt64(Int32.max)))
      var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
      let ready = Darwin.poll(&descriptor, 1, max(1, remaining))
      if ready == 0 { throw CodexUsageError.timeout }
      if ready < 0 {
        if errno == EINTR { continue }
        throw CodexUsageError.serverExited
      }
      var bytes = [UInt8](repeating: 0, count: 8_192)
      let count = Darwin.read(fileDescriptor, &bytes, bytes.count)
      if count == 0 { throw CodexUsageError.serverExited }
      if count < 0 {
        if errno == EINTR { continue }
        throw CodexUsageError.serverExited
      }
      pending.append(contentsOf: bytes[..<count])
      // A runaway server must not hold unbounded private data in memory.
      if pending.count > 1_000_000 { throw CodexUsageError.invalidResponse }
    }
  }
}
