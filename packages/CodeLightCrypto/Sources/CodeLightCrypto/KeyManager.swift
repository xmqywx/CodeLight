import Foundation
import CryptoKit

/// Manages Ed25519 keypairs and encryption keys.
/// Keys are stored in the Keychain for persistence.
public final class KeyManager: Sendable {

    private let serviceName: String

    /// Cached identity private key to avoid repeated Keychain lookups.
    /// Populated on first access, reused for sign() and publicKeyBase64().
    private let cachedIdentityKey: Mutex<Curve25519.Signing.PrivateKey?>

    public init(serviceName: String = "com.codelight.keys") {
        self.serviceName = serviceName
        self.cachedIdentityKey = Mutex(nil)
        migrateKeychainAccessibility()
    }

    /// One-time migration: re-save all existing Keychain items under this service
    /// with an open-access ACL so any app version can read them without prompting.
    /// Ad-hoc signed apps have a different code-signature hash on every update, so
    /// items that use the default app-based ACL always trigger a password dialog
    /// after an update. Calling SecAccessCreate with nil trusted apps removes that
    /// restriction permanently.
    private func migrateKeychainAccessibility() {
        #if os(macOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return }

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data else { continue }

            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(deleteQuery as CFDictionary)

            var addQuery = deleteQuery
            addQuery[kSecValueData as String] = data
            // Open-access ACL: any application can read without password prompt
            var accessRef: SecAccess?
            if SecAccessCreate(serviceName as CFString, nil, &accessRef) == errSecSuccess,
               let accessRef {
                addQuery[kSecAttrAccess as String] = accessRef
            }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            assert(
                addStatus == errSecSuccess || addStatus == errSecDuplicateItem,
                "KeyManager migration: failed to re-save item '\(account)': \(addStatus)"
            )
        }
        #endif
    }

    // MARK: - Ed25519 Identity Key

    /// Generate a new Ed25519 signing keypair and store in Keychain.
    public func generateIdentityKey() throws -> Curve25519.Signing.PublicKey {
        let privateKey = Curve25519.Signing.PrivateKey()
        try saveToKeychain(key: "identity-private", data: privateKey.rawRepresentation)
        cachedIdentityKey.withLock { $0 = privateKey }
        return privateKey.publicKey
    }

    /// Load the existing identity private key from Keychain.
    public func loadIdentityPrivateKey() throws -> Curve25519.Signing.PrivateKey? {
        // Return cached key if available
        if let cached = cachedIdentityKey.withLock({ $0 }) {
            return cached
        }
        guard let data = loadFromKeychain(key: "identity-private") else { return nil }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        cachedIdentityKey.withLock { $0 = key }
        return key
    }

    /// Get or create identity keypair. Returns public key.
    public func getOrCreateIdentityKey() throws -> Curve25519.Signing.PublicKey {
        if let existing = try loadIdentityPrivateKey() {
            return existing.publicKey
        }
        return try generateIdentityKey()
    }

    // MARK: - Signing

    /// Sign data with the identity private key.
    public func sign(_ data: Data) throws -> Data {
        guard let privateKey = try loadIdentityPrivateKey() else {
            throw KeyManagerError.noIdentityKey
        }
        return try privateKey.signature(for: data)
    }

    /// Get public key as base64 string.
    public func publicKeyBase64() throws -> String {
        let publicKey = try getOrCreateIdentityKey()
        return publicKey.rawRepresentation.base64EncodedString()
    }

    // MARK: - Encryption Key Storage (for paired devices)

    /// Store an encryption key for a specific server/device pair.
    public func storeEncryptionKey(_ key: Data, forServer serverUrl: String) throws {
        let keychainKey = "enc-\(serverUrl.hashValue)"
        try saveToKeychain(key: keychainKey, data: key)
    }

    /// Load encryption key for a server.
    public func loadEncryptionKey(forServer serverUrl: String) -> Data? {
        let keychainKey = "enc-\(serverUrl.hashValue)"
        return loadFromKeychain(key: keychainKey)
    }

    // MARK: - Token Storage

    /// Store auth token for a server.
    public func storeToken(_ token: String, forServer serverUrl: String) throws {
        let keychainKey = "token-\(serverUrl.hashValue)"
        try saveToKeychain(key: keychainKey, data: Data(token.utf8))
    }

    /// Load auth token for a server.
    public func loadToken(forServer serverUrl: String) -> String? {
        guard let data = loadFromKeychain(key: "token-\(serverUrl.hashValue)") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Keychain Helpers

    private func saveToKeychain(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        #if os(macOS)
        // On macOS, use SecAccess with nil trusted apps so any app version can read
        // this item without a password prompt. The default behavior ties the ACL to
        // the calling binary's code signature hash, which changes on every ad-hoc
        // re-sign (i.e. every update), causing macOS to prompt for the keychain
        // password on each launch after an update.
        var accessRef: SecAccess?
        let accessStatus = SecAccessCreate(serviceName as CFString, nil, &accessRef)
        if accessStatus == errSecSuccess, let accessRef {
            addQuery[kSecAttrAccess as String] = accessRef
        } else {
            assert(false, "KeyManager: SecAccessCreate failed: \(accessStatus) — item will use default ACL")
        }
        #else
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        #endif

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyManagerError.keychainError(status)
        }
    }

    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}

/// Thread-safe wrapper for mutable state.
private final class Mutex<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

public enum KeyManagerError: Error {
    case noIdentityKey
    case keychainError(OSStatus)
}
