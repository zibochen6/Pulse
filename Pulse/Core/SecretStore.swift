import Foundation
import Security

protocol SecretStoring: Sendable {
  func read(account: String) throws -> String?
  func save(_ secret: String, account: String) throws
  func delete(account: String) throws
}

enum SecretStoreError: LocalizedError, Equatable {
  case unexpectedStatus(OSStatus)
  case invalidStoredValue

  var errorDescription: String? {
    switch self {
    case .unexpectedStatus:
      "The macOS Keychain could not complete the request."
    case .invalidStoredValue:
      "The saved Keychain value could not be read."
    }
  }
}

struct KeychainSecretStore: SecretStoring {
  private let service = "dev.zibochen.Pulse"

  func read(account: String) throws -> String? {
    let query = baseQuery(account: account).merging([
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnData as String: true,
    ]) { _, new in new }
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw SecretStoreError.unexpectedStatus(status) }
    guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
      throw SecretStoreError.invalidStoredValue
    }
    return secret
  }

  func save(_ secret: String, account: String) throws {
    let data = Data(secret.utf8)
    let query = baseQuery(account: account)
    let attributes = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var addQuery = query
      addQuery[kSecValueData as String] = data
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw SecretStoreError.unexpectedStatus(addStatus) }
      return
    }
    guard updateStatus == errSecSuccess else { throw SecretStoreError.unexpectedStatus(updateStatus) }
  }

  func delete(account: String) throws {
    let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw SecretStoreError.unexpectedStatus(status)
    }
  }

  private func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
  }
}
