import Darwin
import Foundation
import os

struct AntigravityCLIResult: Sendable {
  let status: Int32
  let stdout: Data
  let stderr: Data
}

protocol AntigravityCLIReading: Sendable {
  func readUsage() async throws -> AntigravityCLIResult
}

struct AntigravityCLITransport: AntigravityCLIReading {
  var environment = ProcessInfo.processInfo.environment
  var home = NSHomeDirectory()
  var timeout: Duration = .seconds(16)

  func readUsage() async throws -> AntigravityCLIResult {
    let cancelled = OSAllocatedUnfairLock(initialState: false)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
          continuation.resume(with: Result { try run(cancelled: cancelled) })
        }
      }
    } onCancel: {
      cancelled.withLock { $0 = true }
    }
  }

  private func run(cancelled: OSAllocatedUnfairLock<Bool>) throws -> AntigravityCLIResult {
    if cancelled.withLock({ $0 }) { throw CancellationError() }
    guard let binary = AntigravityBinaryLocator.resolve(environment: environment, home: home)
    else { throw AntigravityUsageError.binaryNotFound }

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Pulse-Gemini-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let childEnvironment = try prepareEnvironment(in: directory)
    let version = try runProcess(
      binary, arguments: ["--version"], in: directory, environment: childEnvironment,
      timeout: .seconds(3), cancelled: cancelled)
    guard version.status == 0, Self.supportsUsage(String(decoding: version.stdout, as: UTF8.self))
    else { throw AntigravityUsageError.unsupportedCLI }

    return try runProcess(
      binary,
      arguments: [
        "--disable-slash-commands=false", "-p", "/usage", "--output-format", "json",
        "--print-timeout", "12s",
      ],
      in: directory, environment: childEnvironment, timeout: timeout, cancelled: cancelled)
  }

  private func runProcess(
    _ binary: String, arguments: [String], in directory: URL, environment: [String: String],
    timeout: Duration, cancelled: OSAllocatedUnfairLock<Bool>
  ) throws -> AntigravityCLIResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    if cancelled.withLock({ $0 }) { throw CancellationError() }
    do { try process.run() } catch { throw AntigravityUsageError.launchFailed }
    let pid = process.processIdentifier
    let ownsProcessGroup = Darwin.getpgid(pid) == pid
    var completed = false
    defer {
      // A helper can keep the pipes open after the child has exited.
      if !completed && ownsProcessGroup {
        Darwin.kill(-pid, SIGKILL)
      } else if process.isRunning {
        Darwin.kill(pid, SIGKILL)
      }
      process.waitUntilExit()
    }

    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    var descriptors = [stdout, stderr].map {
      pollfd(
        fd: $0.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
    }
    var output = [Data(), Data()]
    var bytes = [UInt8](repeating: 0, count: 8_192)
    while descriptors.contains(where: { $0.fd >= 0 }) || process.isRunning {
      if cancelled.withLock({ $0 }) { throw CancellationError() }
      guard clock.now < deadline else { throw AntigravityUsageError.timeout }
      // A short poll makes cancellation responsive without blocking either pipe.
      let ready = Darwin.poll(&descriptors, nfds_t(descriptors.count), 50)
      if ready < 0, errno != EINTR { throw AntigravityUsageError.launchFailed }
      guard ready > 0 else { continue }
      for index in descriptors.indices where descriptors[index].revents != 0 {
        let count = Darwin.read(descriptors[index].fd, &bytes, bytes.count)
        if count == 0 {
          descriptors[index].fd = -1
        } else if count > 0 {
          guard output[index].count + count <= 1_048_576
          else { throw AntigravityUsageError.invalidReport }
          output[index].append(contentsOf: bytes[..<count])
        } else if errno != EINTR {
          throw AntigravityUsageError.launchFailed
        }
      }
    }
    if cancelled.withLock({ $0 }) { throw CancellationError() }
    completed = true
    return AntigravityCLIResult(
      status: process.terminationStatus, stdout: output[0], stderr: output[1])
  }

  private static func supportsUsage(_ version: String) -> Bool {
    // Versions before 1.1.11 may treat /usage as model input.
    let parts = version.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
    guard parts.count == 3, let major = Int(parts[0]), let minor = Int(parts[1]),
      let patch = Int(parts[2]), major >= 0, minor >= 0, patch >= 0
    else { return false }
    return (major, minor, patch) >= (1, 1, 11)
  }

  private func prepareEnvironment(in directory: URL) throws -> [String: String] {
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      for name in ["open", "xdg-open"] {
        let helper = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
      }
    } catch {
      throw AntigravityUsageError.launchFailed
    }
    var environment = environment
    environment.removeValue(forKey: "GEMINI_API_KEY")
    environment.removeValue(forKey: "GOOGLE_API_KEY")
    environment["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
    environment["BROWSER"] = directory.appendingPathComponent("open").path
    environment["PATH"] = directory.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
    return environment
  }
}

enum AntigravityBinaryLocator {
  static func resolve(
    environment: [String: String], home: String, fileManager: FileManager = .default
  ) -> String? {
    let pathDirectories = (environment["PATH"] ?? "").split(separator: ":")
      .filter { $0.hasPrefix("/") }
    let appDirectories = ["/Applications", "\(home)/Applications"]
    let bundled = appDirectories.flatMap { directory in
      ["Gemini", "Antigravity"].map { "\(directory)/\($0).app/Contents/Helpers/agy" }
    }
    let candidates =
      ["\(home)/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"]
      + pathDirectories.map { "\($0)/agy" } + bundled
    return candidates.first { path in
      var isDirectory: ObjCBool = false
      return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        && !isDirectory.boolValue && fileManager.isExecutableFile(atPath: path)
    }
  }
}
