import Foundation

@MainActor
final class VIPConfiguration: ObservableObject {
  nonisolated static let keychainAccount = "88VIP API key"

  @Published private(set) var hasAPIKey = false
  @Published private(set) var errorMessage: String?

  private let secretStore: any SecretStoring

  init(secretStore: any SecretStoring = KeychainSecretStore()) {
    self.secretStore = secretStore
  }

  func refresh() {
    do {
      let savedKey = try secretStore.read(account: Self.keychainAccount)
      hasAPIKey = savedKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      errorMessage = nil
    } catch {
      hasAPIKey = false
      errorMessage = "Could not read the saved 88VIP API key from Keychain."
    }
  }

  @discardableResult
  func save(apiKey: String) -> Bool {
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      errorMessage = "Enter an 88VIP API key before saving."
      return false
    }
    do {
      try secretStore.save(trimmed, account: Self.keychainAccount)
      hasAPIKey = true
      errorMessage = nil
      return true
    } catch {
      errorMessage = "Could not save the 88VIP API key to Keychain."
      return false
    }
  }

  @discardableResult
  func removeAPIKey() -> Bool {
    do {
      try secretStore.delete(account: Self.keychainAccount)
      hasAPIKey = false
      errorMessage = nil
      return true
    } catch {
      errorMessage = "Could not remove the 88VIP API key from Keychain."
      return false
    }
  }
}
