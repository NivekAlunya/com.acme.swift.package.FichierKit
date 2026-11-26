//
//  SMBPasswordStoreError.swift
//  FichierKit
//

import Foundation
import Security

/// Typed errors thrown by `SMBPasswordStore` when Keychain persistence fails.
public enum SMBPasswordStoreError: Error, Equatable, Sendable, LocalizedError {
    case keychainWriteFailed(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keychainWriteFailed(let status):
            return "Could not save credentials to Keychain (status: \(status))."
        }
    }
}
