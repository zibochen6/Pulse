import Foundation

@MainActor
class APIKeyConfiguration: ObservableObject {

  @Published private(set) var hasAPIKey = false
  @Published private(set) var errorMessage: String?

  private let providerName: String
  private let account: String
  private let secretStore: any SecretStoring

  init(providerName: String, account: String, secretStore: any SecretStoring) {
    self.providerName = providerName
    self.account = account
    self.secretStore = secretStore
  }

  func refresh() {
    do {
      let savedKey = try secretStore.read(account: account)
      hasAPIKey = savedKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      errorMessage = nil
    } catch {
      hasAPIKey = false
      errorMessage = PulseLocalization.format(
        "Could not read the saved %@ API key from Keychain.", providerName)
    }
  }

  @discardableResult
  func save(apiKey: String) -> Bool {
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
