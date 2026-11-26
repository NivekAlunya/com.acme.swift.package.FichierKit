//
//  MockKeychainCredentialBackend.swift
//  FichierKitTests
//

import Foundation
import Security
import Synchronization
@testable import FichierKit

/// In-memory test double for `KeychainCredentialBackendProtocol` that never touches the system Keychain.
final class MockKeychainCredentialBackend: KeychainCredentialBackendProtocol {
    struct State: Sendable {
        var updateStatus: OSStatus = errSecItemNotFound
        var addStatus: OSStatus = errSecSuccess
        var copyStatus: OSStatus = errSecSuccess
        var deleteStatus: OSStatus = errSecSuccess
        var storedData: [String: Data] = [:]
    }

    private let state: Mutex<State>

    init(
        updateStatus: OSStatus = errSecItemNotFound,
        addStatus: OSStatus = errSecSuccess,
        copyStatus: OSStatus = errSecSuccess,
        deleteStatus: OSStatus = errSecSuccess
    ) {
        self.state = Mutex(
            State(
                updateStatus: updateStatus,
                addStatus: addStatus,
                copyStatus: copyStatus,
                deleteStatus: deleteStatus
            )
        )
    }

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        let account = query[kSecAttrAccount as String] as? String
        let data = attributes[kSecValueData as String] as? Data
        return state.withLock { state in
            if state.updateStatus == errSecSuccess, let account, let data {
                state.storedData[account] = data
            }
            return state.updateStatus
        }
    }

    func add(attributes: [String: Any]) -> OSStatus {
        let account = attributes[kSecAttrAccount as String] as? String
        let data = attributes[kSecValueData as String] as? Data
        return state.withLock { state in
            if state.addStatus == errSecSuccess, let account, let data {
                state.storedData[account] = data
            }
            return state.addStatus
        }
    }

    func copyMatching(query: [String: Any]) -> (status: OSStatus, data: Data?) {
        let account = query[kSecAttrAccount as String] as? String
        return state.withLock { state in
            let data = account.flatMap { state.storedData[$0] }
            return (state.copyStatus, data)
        }
    }

    func delete(query: [String: Any]) -> OSStatus {
        let account = query[kSecAttrAccount as String] as? String
        return state.withLock { state in
            if let account {
                state.storedData.removeValue(forKey: account)
            }
            return state.deleteStatus
        }
    }
}
