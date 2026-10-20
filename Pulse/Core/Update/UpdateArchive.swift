import Foundation

protocol UpdateUnarchiving: Sendable {
  /// Expands the release archive into `directory` and returns its single app
  /// bundle. Anything other than exactly one bundle is rejected so a malformed
  /// or unexpected archive can never be installed.
  func unarchive(_ archiveURL: URL, into directory: URL) throws -> URL
}

/// `ditto` is the only archiver that reliably round-trips a signed, universal
/// app bundle, so the release publishes what `ditto` produced and the updater
/// reads it back with the same tool.
struct DittoUnarchiver: UpdateUnarchiving {
  func unarchive(_ archiveURL: URL, into directory: URL) throws -> URL {
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: directory)
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      throw UpdateVerificationError.unreadableBundle(error.localizedDescription)
    }
    let result = try UpdateShell.run("/usr/bin/ditto", [
      "-x", "-k", archiveURL.path, directory.path,
    ])
    guard result.succeeded else {
      throw UpdateVerificationError.archiveLayout
    }
    let contents =
      (try? fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))
      ?? []
    let bundles = contents.filter { $0.pathExtension == "app" }
    guard bundles.count == 1, let bundle = bundles.first else {
      throw UpdateVerificationError.archiveLayout
    }
    return bundle
  }
}