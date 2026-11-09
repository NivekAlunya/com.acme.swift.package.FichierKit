//
//  SMBPasswordStore.swift
//  FichierKit
//
//

import Foundation
import Security

/// Actor-isolated Keychain credential store with in-memory fallback for unsigned simulator/test environments.
public actor SMBPasswordStore {
    public static let shared = SMBPasswordStore()

    private let service: String
    private var inMemoryFallback: [String: String] = [:]

    public init(service: String = "com.acme.ios.photos.smb") {
        self.service = service
    }

    /// Saves or updates a password in the Keychain for the given account identifier.
    public func savePassword(_ password: String, for account: String) {
        inMemoryFallback[account] = password

        let query = baseQuery(for: account)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let inserted = query.merging(attributes) { _, new in new }
            status = SecItemAdd(inserted as CFDictionary, nil)
        }
        _ = status
    }

    /// Loads a stored password from the Keychain or in-memory fallback.
    public func loadPassword(for account: String) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        return inMemoryFallback[account]
    }

    /// Deletes stored credentials from the Keychain and in-memory fallback.
    public func deletePassword(for account: String) {
        inMemoryFallback.removeValue(forKey: account)
        SecItemDelete(baseQuery(for: account) as CFDictionary)
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
