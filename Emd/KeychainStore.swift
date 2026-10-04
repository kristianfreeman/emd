import Foundation
import Security

enum KeychainStore {
    private static let service = AppIdentity.bundleID
    private static let account = "access-token"
    /// Items with this comment use the default access rule (this app's signing team), not a per-build binary lock.
    private static let marker = "team-access"

    static func save(token: String) throws {
        let data = Data(token.utf8)
        SecItemDelete(baseQuery() as CFDictionary)
        var insert = baseQuery()
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        insert[kSecAttrComment as String] = marker
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw APIError(status: 0, code: "KEYCHAIN", message: "The token could not be saved on this Mac.")
        }
    }

    static func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let fields = item as? [String: Any] else { return nil }
        guard let data = fields[kSecValueData as String] as? Data, let token = String(data: data, encoding: .utf8),
            !token.isEmpty
        else {
            return nil
        }
        let comment = fields[kSecAttrComment as String] as? String
        if comment != marker {
            try? save(token: token)
        }
        return token
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
