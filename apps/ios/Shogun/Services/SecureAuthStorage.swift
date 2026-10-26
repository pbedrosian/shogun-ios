import Foundation
import Security
import Auth

/// Device-bound Keychain storage with idempotent reads/removals for absent items.
/// The SDK's storage protocol allows a missing value; raw Keychain status does not.
struct SecureAuthStorage: AuthLocalStorage {
    let service: String
    init(service: String = "com.petebedrosian.shogun.auth") { self.service = service }
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    func retrieve(key: String) throws -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw SignInFailure.unavailable }
        return data
    }
    func store(key: String, value: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: value, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            try check(SecItemAdd(query(key).merging(attributes) { _, new in new } as CFDictionary, nil))
        } else { try check(status) }
    }
    func remove(key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}
