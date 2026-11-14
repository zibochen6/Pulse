import Combine
import Foundation

/// Session-only input. API keys never enter defaults, files, logs, or task storage.
@MainActor
final class SettingsPresentation: ObservableObject {
  @Published var destination: SettingsDestination
  @Published var expandedProviders = Set<ProviderID>()
  @Published var credentialDrafts: [ProviderID: String] = [:]
  @Published var focusedProvider: ProviderID?
  @Published var revealRequest = UUID()
  private var editorIDs: [ProviderID: UUID] = [:]

  init(destination: SettingsDestination = .general) { self.destination = destination }

  var hasUnsavedEdits: Bool { credentialDrafts.values.contains { !$0.isEmpty } }

  func open(_ destination: SettingsDestination? = nil, provider: ProviderID? = nil) {
    if let destination { self.destination = destination }
    if let provider {
      self.destination = .providers
      if provider != .codex { beginEditing(provider) }
      focusedProvider = provider
      revealRequest = UUID()
    }
  }

  func beginEditing(_ provider: ProviderID) {
    expandedProviders.insert(provider)
    if editorIDs[provider] == nil { editorIDs[provider] = UUID() }
  }
  func editorID(for provider: ProviderID) -> UUID? { editorIDs[provider] }
  func draft(for provider: ProviderID) -> String { credentialDrafts[provider] ?? "" }
  func setDraft(_ value: String, for provider: ProviderID) { credentialDrafts[provider] = value }
  func finishEditing(_ provider: ProviderID) {
    credentialDrafts[provider] = nil
    editorIDs[provider] = nil
    expandedProviders.remove(provider)
    if focusedProvider == provider { focusedProvider = nil }
  }
  func discardAllDrafts() {
    credentialDrafts.removeAll()
    editorIDs.removeAll()
    expandedProviders.removeAll()
    focusedProvider = nil
  }
}

enum ProviderConnectionState: Equatable {
  case notConnected, verifying, connected
  case needsAttention(String)

  static func resolve(
    hasCredential: Bool, configurationError: String? = nil, state: UsageRefreshState
  ) -> Self {
    if let configurationError { return .needsAttention(configurationError) }
    guard hasCredential else { return .notConnected }
    switch state {
    case .loading: return .verifying
    case .success(let snapshot):
      if snapshot.hasPartialDataFailure {
        return .needsAttention(PulseLocalization.string("Some account data is unavailable."))
      }
      return .connected
    case .unavailable(let message), .failure(let message): return .needsAttention(message)
    }
  }

  var title: String {
    switch self {
    case .notConnected: PulseLocalization.string("Not connected")
    case .verifying: PulseLocalization.string("Verifying…")
    case .connected: PulseLocalization.string("Connected")
    case .needsAttention: PulseLocalization.string("Needs attention")
    }
  }
}

/// A render-only default for previews and legacy test call sites. Production
/// injects the already-running provider controllers; this never makes a request.
struct InactiveSettingsProvider: UsageProviding {
  func fetch() async throws -> UsageSnapshot {
    UsageSnapshot(providerID: "inactive", fetchedAt: .now, metrics: [])
  }
}

@MainActor
final class PulseEditingRegistry: ObservableObject {
  @Published private(set) var isEditing = false
  private var sources = Set<String>()
  func set(source: String, editing: Bool) {
    if editing { sources.insert(source) } else { sources.remove(source) }
    isEditing = !sources.isEmpty
  }
  func clear() {
    sources.removeAll()
    isEditing = false
  }
}
