import Foundation

@MainActor
class APIKeyConfiguration: ObservableObject {

  @Published private(set) var hasAPIKey = false
  @Published private(set) var errorMessage: String?

  private let providerName: String
  private let account: String
  private let secretStore: any SecretStoring
  private var revision = 0

  init(providerName: String, account: String, secretStore: any SecretStoring) {
    self.providerName = providerName
    self.account = account
    self.secretStore = secretStore
  }

  func refresh() {
    revision += 1
    applyRead(Result { try Self.readPresence(in: secretStore, account: account) })
  }

  func refreshInBackground() async {
    revision += 1
    let requestedRevision = revision
    let read = await Task.detached(priority: .utility) { [secretStore, account] in
      Result { try Self.readPresence(in: secretStore, account: account) }
    }.value
    guard !Task.isCancelled, requestedRevision == revision else { return }
    applyRead(read)
  }

  private nonisolated static func readPresence(
    in secretStore: any SecretStoring, account: String
  ) throws -> Bool {
    guard let key = try secretStore.read(account: account) else { return false }
    return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func applyRead(_ result: Result<Bool, any Error>) {
    let configured = (try? result.get()) ?? false
    let message: String?
    if case .failure = result {
      message = PulseLocalization.format(
        "Could not read the saved %@ API key from Keychain.", providerName)
    } else {
      message = nil
    }
    if hasAPIKey != configured { hasAPIKey = configured }
    if errorMessage != message { errorMessage = message }
  }

  @discardableResult
  func save(apiKey: String) -> Bool {
    revision += 1
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      errorMessage = PulseLocalization.format("Enter your %@ API key before saving.", providerName)
      return false
    }
    do {
      try secretStore.save(trimmed, account: account)
      hasAPIKey = true
      errorMessage = nil
      return true
    } catch {
      errorMessage = PulseLocalization.format(
        "Could not save the %@ API key to Keychain.", providerName)
      return false
    }
  }

  @discardableResult
  func removeAPIKey() -> Bool {
    revision += 1
    do {
      try secretStore.delete(account: account)
      hasAPIKey = false
      errorMessage = nil
      return true
    } catch {
      errorMessage = PulseLocalization.format(
        "Could not remove the %@ API key from Keychain.", providerName)
      return false
    }
  }
}
