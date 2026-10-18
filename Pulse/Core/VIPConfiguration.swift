import Foundation

@MainActor
final class VIPConfiguration: APIKeyConfiguration {
  nonisolated static let keychainAccount = "88VIP API key"

  init(secretStore: any SecretStoring = KeychainSecretStore()) {
    super.init(
      providerName: "88VIP", account: Self.keychainAccount, article: "an",
      secretStore: secretStore)
  }
}
