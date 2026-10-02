import Darwin
import Foundation

/// Staging and revision validation are separate from the parser so deterministic
/// failure tests can exercise an uncertain save without editing a real Vault.
protocol DashboardDocumentReplacing: Sendable {
  func replace(data: Data, fileURL: URL, validateBeforeReplacing: () throws -> Void) throws
}

struct DashboardAtomicDocumentReplacer: DashboardDocumentReplacing {
  func replace(data: Data, fileURL: URL, validateBeforeReplacing: () throws -> Void) throws {
    let directory = fileURL.deletingLastPathComponent()
    var directoryInfo = stat()
    guard stat(directory.path, &directoryInfo) == 0 else {
      throw DashboardFileStore.posixError(errno, saving: true)
    }
    // Atomic insertion requires a sibling temporary file. We do not fall back
    // to truncating the user's Markdown if the selected directory is unwritable.
    guard directoryInfo.st_mode & 0o222 != 0 else { throw DashboardWriteError.permissionDenied }
    let temporary = directory.appendingPathComponent(".pulse-\(UUID().uuidString).tmp")
    let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw DashboardFileStore.posixError(errno, saving: true) }
    defer {
      close(descriptor)
      try? FileManager.default.removeItem(at: temporary)
    }

    var sourceInfo = stat()
    guard stat(fileURL.path, &sourceInfo) == 0 else {
      throw DashboardFileStore.posixError(errno, saving: true)
    }
    try data.withUnsafeBytes { buffer in
      guard let base = buffer.baseAddress else { throw DashboardWriteError.saveFailed }
      var offset = 0
      while offset < buffer.count {
        let count = write(descriptor, base.advanced(by: offset), buffer.count - offset)
        if count == -1, errno == EINTR { continue }
        guard count > 0 else { throw DashboardFileStore.posixError(errno, saving: true) }
        offset += count
      }
    }
    // Preserve permissions, ACLs and extended attributes across atomic replacement.
    guard fchown(descriptor, sourceInfo.st_uid, sourceInfo.st_gid) == 0,
      fchmod(descriptor, sourceInfo.st_mode & 0o7777) == 0,
      copyfile(fileURL.path, temporary.path, nil, copyfile_flags_t(COPYFILE_ACL | COPYFILE_XATTR))
        == 0
    else { throw DashboardFileStore.posixError(errno, saving: true) }
    try synchronize(descriptor)
    try validateBeforeReplacing()
    guard rename(temporary.path, fileURL.path) == 0 else {
      throw DashboardFileStore.posixError(errno, saving: true)
    }
    let directoryDescriptor = open(directory.path, O_RDONLY | O_CLOEXEC)
    guard directoryDescriptor >= 0 else { throw DashboardWriteError.saveFailed }
    defer { close(directoryDescriptor) }
    try synchronize(directoryDescriptor)
  }

  private func synchronize(_ descriptor: Int32) throws {
    var result: Int32
    repeat { result = fsync(descriptor) } while result == -1 && errno == EINTR
    guard result == 0 else { throw DashboardFileStore.posixError(errno, saving: true) }
  }
}
