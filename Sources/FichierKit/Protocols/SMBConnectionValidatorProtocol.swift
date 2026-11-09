//
//  SMBConnectionValidatorProtocol.swift
//  FichierKit
//
//

import Foundation

/// Protocol verifying SMB reachability, credentials, and accessible shares prior to persistence.
public protocol SMBConnectionValidatorProtocol: Sendable {
    /// Connects to `server` with `password` and returns non-hidden share names.
    func validateAndListShares(for server: SavedSMBConnection, password: String) async throws -> [String]
}
