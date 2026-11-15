import Foundation
import Security
import CommonCrypto

// Independent local six-digit+ access code. No hard-coded backdoor password.
// This is a privacy gate; the PC still requires normal bearer authentication.
enum PrivateAccessStore {
    private static let service = "com.adri23rep.applecontroller.private-player.v1"
    private static let account = "local-access-code"
    private static let saltLength = 16
    private static let hashLength = 32
    private static let rounds: UInt32 = 150_000

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func isConfigured() -> Bool {
        return stored() != nil
    }

    private static func stored() -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              data.count == saltLength + hashLength else { return nil }
        return data
    }

    private static func derivation(_ password: String, salt: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: hashLength)
        let code = password.utf8CString
        let result = code.withUnsafeBufferPointer { cstr in
            salt.withUnsafeBufferPointer { saltData in
                output.withUnsafeMutableBufferPointer { digest in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        cstr.baseAddress, code.count - 1,
                        saltData.baseAddress, saltLength,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds, digest.baseAddress, hashLength)
                }
            }
        }
        return result == kCCSuccess ? output : nil
    }

    static func valid(_ code: String) -> Bool {
        (6...12).contains(code.count) && code.allSatisfy {
            $0 >= "0" && $0 <= "9"
        }
    }

    @discardableResult
    static func configure(_ code: String) -> Bool {
        guard valid(code) else { return false }
        var salt = [UInt8](repeating: 0, count: saltLength)
        let generated = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) == errSecSuccess
        }
        guard generated, let hash = derivation(code, salt: salt) else { return false }
        let data = Data(salt + hash)
        let updated = SecItemUpdate(query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var entry = query
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(entry as CFDictionary, nil) == errSecSuccess
    }

    static func verify(_ code: String) -> Bool {
        guard valid(code), let data = stored() else { return false }
        let bytes = [UInt8](data)
        let salt = Array(bytes.prefix(saltLength))
        guard let expected = derivation(code, salt: salt) else { return false }
        var difference: UInt8 = 0
        for index in 0..<hashLength {
            difference |= expected[index] ^ bytes[saltLength + index]
        }
        return difference == 0
    }
}
