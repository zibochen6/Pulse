import Darwin
import Foundation

enum DashboardWriteError: LocalizedError, Equatable, Sendable {
  case fileMissing
  case permissionDenied
  case unsupportedEncoding
  case unsupportedState
  case conflict
  case busy
  case readFailed
  case saveFailed
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .fileMissing: "The Dashboard file is unavailable. Choose it again in Settings."
    case .permissionDenied:
      "Pulse cannot save this file. Check file permissions or choose it again in Settings."
    case .unsupportedEncoding:
      "Pulse can only update UTF-8 Dashboard files. This file was not changed."
    case .unsupportedState: "This task uses a special checkbox state. Update it in Obsidian."
    case .conflict:
      "The Dashboard changed and this task cannot be identified safely. Review the refreshed list."
    case .busy: "Another editor is saving this file. Try again after it finishes."
    case .readFailed: "Pulse could not read the Dashboard. Try refreshing or choose the file again."
    case .saveFailed: "Pulse could not confirm the save. Review the file and try again."
    case .verificationFailed:
      "The file changed during saving. Pulse could not confirm the result; review the refreshed list."
    }
  }
}

protocol DashboardFileStoring: Sendable {
  func load(fileURL: URL) async throws -> Dashboard
  func setCompleted(_ completed: Bool, task: DashboardTask, snapshot: Dashboard, fileURL: URL)
    async throws -> Dashboard
}

/// Small injectable I/O boundary for deterministic save/flush failure tests.
protocol DashboardByteWriting: Sendable {
  func write(descriptor: Int32, byte: UInt8, offset: Int) throws
}

struct DashboardPOSIXByteWriter: DashboardByteWriting {
  func write(descriptor: Int32, byte: UInt8, offset: Int) throws {
    var byte = byte
    var count: Int
    repeat {
      count = pwrite(descriptor, &byte, 1, off_t(offset))
    } while count == -1 && errno == EINTR
    guard count == 1 else { throw DashboardWriteError.saveFailed }
    var result: Int32
    repeat { result = fsync(descriptor) } while result == -1 && errno == EINTR
    guard result == 0 else { throw DashboardWriteError.saveFailed }
  }
}

/// The shared serial queue covers read → locate → write → verify as one operation.
/// An actor alone would allow reentrancy at awaits and is insufficient for this.
final class DashboardFileStore: DashboardFileStoring, Sendable {
  private static let queue = DispatchQueue(
    label: "dev.zibochen.Pulse.dashboard-files", qos: .userInitiated)
  private let parser: ApexDashboardParser
  private let writer: any DashboardByteWriting

  init(
    parser: ApexDashboardParser = ApexDashboardParser(),
    writer: any DashboardByteWriting = DashboardPOSIXByteWriter()
  ) {
    self.parser = parser
    self.writer = writer
  }

  func load(fileURL: URL) async throws -> Dashboard {
    try await enqueue { [self] in
      try withAccess(fileURL) {
        try coordinated(fileURL, writing: false) { url in
          let first = try read(url)
          guard try read(url) == first else { throw DashboardWriteError.conflict }
          return try parser.parse(data: first, fileURL: url)
        }
      }
    }
  }

  func setCompleted(_ completed: Bool, task: DashboardTask, snapshot: Dashboard, fileURL: URL)
    async throws -> Dashboard
  {
    try await enqueue { [self] in
      guard task.canToggle else { throw DashboardWriteError.unsupportedState }
      return try withAccess(fileURL) {
        try coordinated(fileURL, writing: true) { url in
          try patch(completed: completed, task: task, snapshot: snapshot, fileURL: url)
        }
      }
    }
  }

  private func enqueue(_ operation: @escaping @Sendable () throws -> Dashboard) async throws
    -> Dashboard
  {
    try await withCheckedThrowingContinuation { continuation in
      Self.queue.async {
        continuation.resume(
          with: Result {
            var dashboard = try operation()
            dashboard.observedAt = ContinuousClock.now
            return dashboard
          })
      }
    }
  }

  private func withAccess<T>(_ url: URL, operation: () throws -> T) throws -> T {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    // Ordinary bookmarks in this non-sandboxed app legitimately return false.
    // The actual open/read/write enforces POSIX, ACL and available sandbox rights.
    return try operation()
  }

  private func coordinated<T>(_ url: URL, writing: Bool, operation: (URL) throws -> T) throws -> T {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var result: Result<T, Error>?
    if writing {
      coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) {
        coordinatedURL in
        result = Result { try operation(coordinatedURL) }
      }
    } else {
      coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
        coordinatedURL in
        result = Result { try operation(coordinatedURL) }
      }
    }
    if let coordinationError { throw Self.fileError(coordinationError, saving: writing) }
    guard let result else { throw DashboardWriteError.readFailed }
    return try result.get()
  }

  private func read(_ url: URL) throws -> Data {
    do { return try Data(contentsOf: url) } catch { throw Self.fileError(error, saving: false) }
  }

  private func patch(completed: Bool, task: DashboardTask, snapshot: Dashboard, fileURL: URL) throws
    -> Dashboard
  {
    let descriptor = open(fileURL.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw Self.posixError(errno, saving: true) }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw DashboardWriteError.busy }
    defer { flock(descriptor, LOCK_UN) }

    var initial = stat()
    guard fstat(descriptor, &initial) == 0 else { throw DashboardWriteError.readFailed }
    guard (initial.st_mode & S_IFMT) == S_IFREG else { throw DashboardWriteError.readFailed }
    guard (initial.st_mode & 0o222) != 0 else { throw DashboardWriteError.permissionDenied }
    let bytes = try read(fileURL)
    let latest = try parser.parse(data: bytes, fileURL: fileURL)
    let target = try DashboardTaskLocator.locate(task, from: snapshot, in: latest)
    guard let source = target.source, source.isOrdinaryCheckbox else {
      throw DashboardWriteError.unsupportedState
    }
    guard bytes.indices.contains(source.stateByteOffset),
      bytes[source.stateByteOffset] == source.marker
    else {
      throw DashboardWriteError.conflict
    }

    // Check both path and open descriptor: a concurrent atomic replacement must
    // not send our patch to a detached inode. Never truncate or rewrite the file.
    try verifyRevision(fileURL, descriptor: descriptor, expected: bytes, initial: initial)
    if target.completed == completed { return latest }
    var expected = bytes
    expected[source.stateByteOffset] = completed ? 120 : 32
    try writer.write(
      descriptor: descriptor, byte: expected[source.stateByteOffset], offset: source.stateByteOffset
    )

    do {
      var current = stat()
      guard stat(fileURL.path, &current) == 0, current.st_ino == initial.st_ino,
        current.st_dev == initial.st_dev,
        try read(fileURL) == expected
      else { throw DashboardWriteError.verificationFailed }
      let verified = try parser.parse(data: expected, fileURL: fileURL)
      guard
        let verifiedTask = verified.allTasks.first(where: { $0.lineNumber == target.lineNumber }),
        verifiedTask.completed == completed
      else { throw DashboardWriteError.verificationFailed }
      return verified
    } catch { throw DashboardWriteError.verificationFailed }
  }

  private func verifyRevision(_ url: URL, descriptor: Int32, expected: Data, initial: stat) throws {
    var pathInfo = stat()
    var handleInfo = stat()
    guard stat(url.path, &pathInfo) == 0, fstat(descriptor, &handleInfo) == 0,
      pathInfo.st_ino == initial.st_ino, pathInfo.st_dev == initial.st_dev,
      handleInfo.st_size == initial.st_size,
      handleInfo.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec,
      handleInfo.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec,
      handleInfo.st_ctimespec.tv_sec == initial.st_ctimespec.tv_sec,
      handleInfo.st_ctimespec.tv_nsec == initial.st_ctimespec.tv_nsec,
      try read(url) == expected
    else { throw DashboardWriteError.conflict }
  }

  private static func fileError(_ error: Error, saving: Bool) -> DashboardWriteError {
    let error = error as NSError
    if error.domain == NSPOSIXErrorDomain { return posixError(Int32(error.code), saving: saving) }
    if error.domain == NSCocoaErrorDomain {
      switch error.code {
      case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .fileMissing
      case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return .permissionDenied
      default: break
      }
    }
    return saving ? .saveFailed : .readFailed
  }

  private static func posixError(_ code: Int32, saving: Bool) -> DashboardWriteError {
    switch code {
    case ENOENT: .fileMissing
    case EACCES, EPERM, EROFS: .permissionDenied
    default: saving ? .saveFailed : .readFailed
    }
  }
}
