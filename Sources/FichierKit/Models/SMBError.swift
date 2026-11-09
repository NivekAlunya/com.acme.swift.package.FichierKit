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
            return "Server '\(host)' is unreachable. Please verify that the server is powered on and connected to the local network."
        case .badCredentials:
            return "Authentication failed. The username or password provided is incorrect."
        case .timeout:
            return "Connection timed out. The server took too long to respond."
        case .noShares:
            return "No shared folders were found on this server."
        case .shareNotFound(let share):
            return "Share '\(share)' was not found on this server."
        case .unknown(let message):
            return message
        }
    }
}
