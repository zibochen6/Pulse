import Combine
import Darwin
import Foundation

enum ClipPhase: String, Codable {
  case idle, starting, running, checking, completed, attention, failed, noClip

  var isActive: Bool { self == .starting || self == .running || self == .checking }

  var title: String {
    let key =
      switch self {
      case .idle: "Edit recording"
      case .starting: "Starting…"
      case .running: "Editing…"
      case .checking: "Checking results"
      case .completed: "Drafts verified"
      case .attention: "Needs attention"
      case .failed: "Editing stopped"
      case .noClip: "No new recording"
      }
    return PulseLocalization.string(key)
  }
}

struct ClipDraft: Codable, Equatable {
  var platform: String
  var status: String
  var detail: String
}

struct ClipSnapshot: Codable, Equatable {
  var id = UUID().uuidString
  var phase: ClipPhase = .idle
  var source = ""
  var started = Date.now.timeIntervalSince1970
  var updated = Date.now.timeIntervalSince1970
  var activity: String?
  var detail: String?
  var model: String?
  var effort: String?
  var folder: String?
  var review: String?
  var platforms: [ClipDraft] = []

  var folderURL: URL? {
    guard let folder, FileManager.default.fileExists(atPath: folder) else { return nil }
    return URL(fileURLWithPath: folder, isDirectory: true)
  }

  var reviewURL: URL? {
    guard let review, let folderURL else { return nil }
    let url = URL(fileURLWithPath: review).resolvingSymlinksInPath()
    guard url.path.hasPrefix(folderURL.resolvingSymlinksInPath().path + "/"),
      url.pathExtension.lowercased() == "html", FileManager.default.fileExists(atPath: url.path)
    else { return nil }
    return url
  }
}

enum RecordingSelection {
  static func latest(in directory: URL, after cutoff: TimeInterval = 0) throws -> URL? {
    let keys: Set<URLResourceKey> = [
      .isRegularFileKey, .isSymbolicLinkKey, .addedToDirectoryDateKey, .contentModificationDateKey,
      .creationDateKey, .fileSizeKey,
    ]
    let entries = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)
    var latest: (added: Date, modified: Date, url: URL)?
    for url in entries
    where url.lastPathComponent.range(
      of: #"^(rec_[0-9]+\.mp4|img_[0-9]+\.mov)$"#, options: [.regularExpression, .caseInsensitive]
    ) != nil {
      guard let values = try? url.resourceValues(forKeys: keys),
        values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) > 0
      else { continue }
      let modified = values.contentModificationDate ?? .distantPast
      let added = values.addedToDirectoryDate ?? values.creationDate ?? modified
      guard added.timeIntervalSince1970 > cutoff else { continue }
      let candidate = (added, modified, url.lastPathComponent)
      if let latest, candidate <= (latest.added, latest.modified, latest.url.lastPathComponent) {
        continue
      }
      latest = (added, modified, url)
    }
    return latest?.url
  }
}

@MainActor
final class ClipController: ObservableObject {
  static let defaultModel = "gpt-6.2-sol"
  static let efforts = ["low", "medium", "high", "xhigh", "max", "ultra"]
  static let skill = ".agents/skills/talking-head-autoclip/SKILL.md"
  private static let doneResultKey = "clipDoneResultID"

  @Published var workspace: String { didSet { defaults.set(workspace, forKey: "clipWorkspace") } }
  @Published var model: String { didSet { defaults.set(model, forKey: "clipModel") } }
  @Published var effort: String { didSet { defaults.set(effort, forKey: "clipEffort") } }
  @Published private(set) var snapshot = ClipSnapshot()
  @Published private var doneResultID: String?
  private(set) var previousResult: ClipSnapshot?
  private let defaults: UserDefaults
  private let support: URL
  private let downloads: URL
  private let live: Bool
  private let tools: () throws -> (python: URL, codex: String)
  private var permissionRequestedFor: String?
  private var worker: Process?
  private var polling: Task<Void, Never>?
  var onFinish: (ClipSnapshot) -> Void = { _ in }
  var requestNotifications: () -> Void = {}

  init(
    defaults: UserDefaults, support: URL, downloads: URL, live: Bool,
    tools: @escaping () throws -> (python: URL, codex: String) = {
      let python = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".talking-head-autoclip/venv/bin/python")
      return (python, try CodexBinaryLocator.resolveForLaunch())
    }
  ) {
    self.defaults = defaults
    self.support = support
    self.downloads = downloads
    self.live = live
    self.tools = tools
    workspace = defaults.string(forKey: "clipWorkspace") ?? ""
    model = defaults.string(forKey: "clipModel") ?? Self.defaultModel
    effort = defaults.string(forKey: "clipEffort") ?? "low"
    doneResultID = defaults.string(forKey: Self.doneResultKey)
  }

  static func production(defaults: UserDefaults, live: Bool) -> ClipController {
    let fm = FileManager.default
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return ClipController(
      defaults: defaults, support: base.appendingPathComponent("Pulse/ClipJobs"),
      downloads: fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0], live: live)
  }

  var hasWorkspace: Bool {
    !workspace.isEmpty
      && FileManager.default.fileExists(
        atPath: URL(fileURLWithPath: workspace).appendingPathComponent(Self.skill).path)
  }

  var canMarkResultDone: Bool {
    snapshot.phase == .completed || snapshot.phase == .attention
  }

  var isResultDone: Bool { canMarkResultDone && snapshot.id == doneResultID }

  func markResultDone(id: String) {
    guard canMarkResultDone, snapshot.id == id, !isResultDone else { return }
    defaults.set(id, forKey: Self.doneResultKey)
    doneResultID = id
  }

  func restore() {
    guard live, let saved = readSnapshot() else { return }
    snapshot = saved
    if saved.folderURL != nil { previousResult = saved }
    if saved.phase.isActive {
      if isLocked {
        poll()
      } else {
        fail("The editing worker stopped. Open its files before retrying.")
        notifyOnce(snapshot)
      }
    } else {
      notifyOnce(saved)
    }
  }

  func start() {
    guard live, !snapshot.phase.isActive else { return }
    if isLocked {
      if let saved = readSnapshot(), saved.phase.isActive {
        snapshot = saved
      } else {
        snapshot = ClipSnapshot(phase: .starting)
      }
      poll()
      return
    }
    snapshot = ClipSnapshot(phase: .starting, model: model, effort: effort)
    guard hasWorkspace else {
      fail("Choose a workspace containing the editing skill.")
      return
    }
    let selected = model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !selected.isEmpty, Self.efforts.contains(effort) else {
      fail("Choose a model and reasoning effort in Settings.")
      return
    }
    let cutoff = defaults.double(forKey: "clipIgnoreAddedThrough")
    let root = workspace
    let reasoning = effort
    let directory = downloads
    Task {
      do {
        let recording = try await Task.detached(priority: .userInitiated) {
          try RecordingSelection.latest(in: directory, after: cutoff)
        }.value
        guard let recording else {
          snapshot.phase = .noClip
          return
        }
        try launch(recording, workspace: root, model: selected, effort: reasoning)
      } catch {
        fail(error.localizedDescription)
      }
    }
  }

  private func launch(_ source: URL, workspace: String, model: String, effort: String) throws {
    snapshot.source = source.lastPathComponent
    let (python, binary) = try tools()
    let fm = FileManager.default
    guard fm.isExecutableFile(atPath: python.path) else {
      fail("Install the editing skill’s Python environment first.")
      return
    }
    guard let script = Bundle.main.url(forResource: "clip_worker", withExtension: "py") else {
      fail("The editing worker is missing.")
      return
    }
    try fm.createDirectory(at: support, withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = python
    process.arguments = [
      "-I", script.path, "--workspace", workspace, "--source", source.path,
      "--codex", binary, "--support", support.path, "--model", model, "--effort", effort,
      "--id", snapshot.id, "--language", Bundle.main.preferredLocalizations.first ?? "en",
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try process.run()
    worker = process
    poll()
  }

  private func fail(_ message: String) {
    snapshot.phase = .failed
    snapshot.detail = PulseLocalization.string(message)
  }

  private func readSnapshot() -> ClipSnapshot? {
    guard let data = try? Data(contentsOf: support.appendingPathComponent("latest.json"))
    else { return nil }
    return try? JSONDecoder().decode(ClipSnapshot.self, from: data)
  }

  private var isLocked: Bool {
    let fd = open(support.appendingPathComponent("worker.lock").path, O_RDONLY)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    guard flock(fd, LOCK_SH | LOCK_NB) == 0 else { return errno == EWOULDBLOCK }
    flock(fd, LOCK_UN)
    return false
  }

  private func notifyOnce(_ result: ClipSnapshot) {
    guard defaults.string(forKey: "clipNotifiedID") != result.id else { return }
    defaults.set(result.id, forKey: "clipNotifiedID")
    onFinish(result)
  }

  private func poll() {
    polling?.cancel()
    polling = Task { [weak self] in
      while !Task.isCancelled {
        guard self?.refresh() == true else { return }
        try? await Task.sleep(for: .milliseconds(400))
      }
    }
  }

  private func refresh() -> Bool {
    let locked = isLocked
    if let process = worker, !process.isRunning, process.terminationStatus == EX_TEMPFAIL {
      worker = nil  // Another Pulse instance acquired the job lock first.
    }
    let alive = worker?.isRunning == true || locked
    if let saved = readSnapshot(),
      saved.id == snapshot.id || (worker == nil && (saved.phase.isActive || !locked))
    {
      if saved != snapshot { snapshot = saved }
      if saved.phase == .running, permissionRequestedFor != saved.id {
        permissionRequestedFor = saved.id
        requestNotifications()
      }
      if !saved.phase.isActive {
        if saved.folderURL != nil { previousResult = saved }
        notifyOnce(saved)
        worker = nil
        return false
      }
    }
    if !alive {
      fail("The editing worker stopped. Open its files before retrying.")
      worker = nil
      notifyOnce(snapshot)
      return false
    }
    return true
  }
}
