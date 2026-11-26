//
//  KeychainCredentialBackendProtocol.swift
//  FichierKit
//

import Foundation
import Security

/// Abstraction over Keychain Services calls to enable isolated unit testing without touching the system Keychain.
protocol KeychainCredentialBackendProtocol: Sendable {
    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(attributes: [String: Any]) -> OSStatus
    func copyMatching(query: [String: Any]) -> (status: OSStatus, data: Data?)
    func delete(query: [String: Any]) -> OSStatus
}
