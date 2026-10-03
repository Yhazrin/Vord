import Foundation
import Security

enum KeychainError: LocalizedError, Equatable {
    case status(OSStatus)
    var errorDescription: String? {
        if case .status(let status) = self {
            return "Keychain: " + ((SecCopyErrorMessageString(status, nil) as String?) ?? "error \(status)")
        }
        return nil
    }
}

enum KeychainStore {
    static let service = "app.vord.macos.ai-provider"

    static func set(account: String, secret: String, service: String = service) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(account: account, service: service)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainError.status(updated) }
        var insert = query
        insert[kSecValueData as String] = data
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func get(account: String, service: String = service) throws -> String? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.status(status)
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String, service: String = service) throws {
        let status = SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
