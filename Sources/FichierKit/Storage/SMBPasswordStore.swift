//
//  SMBPasswordStore.swift
//  FichierKit
//
//

import Foundation
import Security

/// Actor-isolated Keychain credential store with an in-memory fallback restricted to simulator and test environments.
public actor SMBPasswordStore {
    public static let shared = SMBPasswordStore()

    #if targetEnvironment(simulator)
    private static let defaultAllowInMemoryFallback = true
    #else
    private static let defaultAllowInMemoryFallback = false
    #endif

    private let service: String
    private let allowInMemoryFallback: Bool
    private let backend: any KeychainCredentialBackendProtocol
    private var inMemoryFallback: [String: String] = [:]

    public init(service: String = "com.acme.ios.photos.smb") {
        self.service = service
        self.allowInMemoryFallback = Self.defaultAllowInMemoryFallback
        self.backend = SystemKeychainCredentialBackend()
    }

    init(
        service: String = "com.acme.ios.photos.smb",
        allowInMemoryFallback: Bool,
        backend: any KeychainCredentialBackendProtocol
    ) {
        self.service = service
        self.allowInMemoryFallback = allowInMemoryFallback
        self.backend = backend
    }

    /// Saves or updates a password in the Keychain for the given account identifier.
    ///
    /// On real devices (`allowInMemoryFallback == false`), any Keychain write failure throws
    /// `SMBPasswordStoreError.keychainWriteFailed(status:)` rather than keeping credentials only in memory.
    public func savePassword(_ password: String, for account: String) throws {
        let query = baseQuery(for: account)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]

        var status = backend.update(query: query, attributes: attributes)
        if status == errSecItemNotFound {
            let inserted = query.merging(attributes) { _, new in new }
            status = backend.add(attributes: inserted)
        }

        if status == errSecSuccess {
            inMemoryFallback.removeValue(forKey: account)
            return
        }

        guard allowInMemoryFallback else {
            throw SMBPasswordStoreError.keychainWriteFailed(status: status)
        }

        // Retain in-memory fallback only in simulator/test environments when Keychain entitlements are unavailable.
        inMemoryFallback[account] = password
    }

    /// Loads a stored password from the Keychain or (in simulator/test environments) the in-memory fallback.
    public func loadPassword(for account: String) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let result = backend.copyMatching(query: query)
        if result.status == errSecSuccess,
           let data = result.data,
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        // Only fall back to in-memory store in simulator/test environments when credential is absent or Keychain is unavailable.
        if allowInMemoryFallback,
           result.status == errSecItemNotFound || result.status == errSecNotAvailable || result.status == errSecMissingEntitlement {
            return inMemoryFallback[account]
        }

        return nil
    }

    /// Deletes stored credentials from the Keychain and in-memory fallback.
    public func deletePassword(for account: String) {
        inMemoryFallback.removeValue(forKey: account)
        _ = backend.delete(query: baseQuery(for: account))
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
