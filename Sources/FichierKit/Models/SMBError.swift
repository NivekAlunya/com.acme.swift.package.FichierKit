//
//  SMBError.swift
//  FichierKit
//

import Foundation

/// Specific failure modes encountered during SMB server connectivity, authentication, and browsing.
public enum SMBError: LocalizedError, Sendable, Equatable {
    case unreachable(String)
    case badCredentials
    case timeout
    case noShares
    case shareNotFound(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let host):
            return String(localized: .smbErrorUnreachable(host))
        case .badCredentials:
            return String(localized: .smbErrorBadCredentials)
        case .timeout:
            return String(localized: .smbErrorTimeout)
        case .noShares:
            return String(localized: .smbErrorNoShares)
        case .shareNotFound(let share):
            return String(localized: .smbErrorShareNotFound(share))
        case .unknown(let message):
            return message
        }
    }
}
