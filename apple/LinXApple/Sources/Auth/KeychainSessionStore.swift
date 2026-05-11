import Foundation
import Security

struct StoredAuthSessionMetadata: Codable, Equatable, Sendable {
    let webID: String
    let clientID: String
}

final class KeychainSessionStore {
    private enum Key {
        static let authState = "authState"
        static let sessionMetadata = "sessionMetadata"
        static let registeredClientID = "registeredClientID"
    }

    private let service = "\(AppConstants.bundleIdentifier).session"

    func saveAuthState(_ data: Data) throws {
        try set(data: data, account: Key.authState)
    }

    func loadAuthState() throws -> Data? {
        try data(for: Key.authState)
    }

    func saveSessionMetadata(_ metadata: StoredAuthSessionMetadata) throws {
        let data = try JSONEncoder().encode(metadata)
        try set(data: data, account: Key.sessionMetadata)
    }

    func loadSessionMetadata() throws -> StoredAuthSessionMetadata? {
        guard let data = try data(for: Key.sessionMetadata) else {
            return nil
        }
        return try JSONDecoder().decode(StoredAuthSessionMetadata.self, from: data)
    }

    func saveRegisteredClientID(_ clientID: String) throws {
        try set(data: Data(clientID.utf8), account: Key.registeredClientID)
    }

    func loadRegisteredClientID() throws -> String? {
        guard let data = try data(for: Key.registeredClientID) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func clearSession() {
        [Key.authState, Key.sessionMetadata].forEach(delete)
    }

    func clearAll() {
        [Key.authState, Key.sessionMetadata, Key.registeredClientID].forEach(delete)
    }

    private func set(data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LinxAppError.authFailed("Failed to write secure session data.")
        }
    }

    private func data(for account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw LinxAppError.authFailed("Failed to read secure session data.")
        }
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
