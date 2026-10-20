import Foundation

/// Small wrapper around `Process` for the macOS tools the updater relies on.
/// Output is captured so callers can parse `codesign` reports.
enum UpdateShell {
  struct Output: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
    var combined: String { stdout + stderr }
    var succeeded: Bool { status == 0 }
  }

  @discardableResult
  static func run(_ executable: String, _ arguments: [String]) throws -> Output {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError
    do {
      try process.run()
    } catch {
      throw UpdateVerificationError.unreadableBundle(
        "Could not run \(executable): \(error.localizedDescription)")
    }
    // The tools used here (ditto, codesign, open) emit well under a pipe
    // buffer, so reading each descriptor to EOF before waiting cannot deadlock.
    let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
    let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Output(
      status: process.terminationStatus,
      stdout: String(decoding: outputData, as: UTF8.self),
      stderr: String(decoding: errorData, as: UTF8.self)
    )
  }
}