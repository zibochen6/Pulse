import Foundation

@MainActor
class APIKeyConfiguration: ObservableObject {

  @Published private(set) var hasAPIKey = false
  @Published private(set) var errorMessage: String?

  private let providerName: String
  private let account: String
  private let article: String
  private let secretStore: any SecretStoring

  init(providerName: String, account: String, article: String, secretStore: any SecretStoring) {
    self.providerName = providerName
    self.account = account
    self.article = article
    self.secretStore = secretStore
  }

  func refresh() {
    do {
      let savedKey = try secretStore.read(account: account)
      hasAPIKey = savedKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      errorMessage = nil
    } catch {
      hasAPIKey = false
      errorMessage = "Could not read the saved \(providerName) API key from Keychain."
    }
  }

  @discardableResult
  func save(apiKey: String) -> Bool {
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      errorMessage = "Enter \(article) \(providerName) API key before saving."
      return false
    }
    do {
      try secretStore.save(trimmed, account: account)
      hasAPIKey = true
      errorMessage = nil
      return true
    } catch {
      errorMessage = "Could not save the \(providerName) API key to Keychain."
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
      errorMessage = "Could not remove the \(providerName) API key from Keychain."
      return false
    }
  }
}
