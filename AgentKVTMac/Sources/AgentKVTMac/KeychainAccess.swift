import Foundation
import Security

/// Thin wrapper around the macOS Keychain for storing and reading agent secrets.
/// Use `store` on first setup; `read` replaces plain-text plist reads for
/// high-value credentials (IMAP password, Anthropic API key).
///
/// The service name scopes all items to this runner process so they don't
/// collide with other apps using generic-password storage.
enum KeychainAccess {
    static let service = "com.agentkvt.runner"

    enum KeychainError: Error, CustomStringConvertible {
        case writeFailed(OSStatus)
        case unexpectedData

        var description: String {
            switch self {
            case .writeFailed(let s): return "Keychain write failed: OSStatus \(s)"
            case .unexpectedData: return "Keychain item contained unexpected data"
            }
        }
    }

    /// Stores (or updates) a secret in the Keychain.
    static func store(secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Try updating an existing item first.
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.writeFailed(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.writeFailed(updateStatus)
        }
    }

    /// Returns the secret stored for `account`, or `nil` if not found.
    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    /// Deletes the item for `account`. No-op if it does not exist.
    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
