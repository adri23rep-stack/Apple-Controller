import Foundation
import Security

enum KeychainStore {
    // Never change the service string or bundle identifier between IPA builds:
    // updates then recover the same device-bound credential automatically.
    private static let service = "com.adri23rep.applecontroller.pairing"

    private static func query(for host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host
        ]
    }

    static func load(for host: String) -> String? {
        var request = query(for: host)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func store(_ token: String, for host: String) -> Bool {
        guard token.count == 64 else { return false }
        let request = query(for: host)
        let bytes = Data(token.utf8)
        // Updating existing Keychain entries is atomic and avoids a temporary
        // gap during repeated pairings, reinstalls or profile migrations.
        let updated = SecItemUpdate(request as CFDictionary,
                                    [kSecValueData as String: bytes] as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }

        var entry = request
        entry[kSecValueData as String] = bytes
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(entry as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(for host: String) -> Bool {
        let code = SecItemDelete(query(for: host) as CFDictionary)
        return code == errSecSuccess || code == errSecItemNotFound
    }
}
