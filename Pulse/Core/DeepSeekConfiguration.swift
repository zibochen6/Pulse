import Foundation

@MainActor
final class DeepSeekConfiguration: APIKeyConfiguration {
  nonisolated static let keychainAccount = "DeepSeek API key"

  init(secretStore: any SecretStoring = KeychainSecretStore()) {
    super.init(
      providerName: "DeepSeek", account: Self.keychainAccount, article: "a",
      secretStore: secretStore)
  }
}
