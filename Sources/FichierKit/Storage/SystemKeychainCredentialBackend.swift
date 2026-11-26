//
//  SystemKeychainCredentialBackend.swift
//  FichierKit
//

import Foundation
import Security

/// Production `KeychainCredentialBackendProtocol` backed by Apple Security framework `SecItem*` APIs.
struct SystemKeychainCredentialBackend: KeychainCredentialBackendProtocol {
    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func add(attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func copyMatching(query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    func delete(query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
