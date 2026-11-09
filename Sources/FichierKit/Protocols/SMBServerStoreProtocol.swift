//
//  SMBServerStoreProtocol.swift
//  FichierKit
//

import Foundation

/// Contract for managing persisted SMB server connections.
public protocol SMBServerStoreProtocol: Sendable {
    /// Loads all persisted SMB connections sorted by most recently used.
    func loadServers() async -> [SavedSMBConnection]

    /// Saves or updates a validated SMB server connection.
    func saveServer(_ server: SavedSMBConnection, password: String) async throws

    /// Removes a saved SMB server connection and its associated credentials.
    func removeServer(_ server: SavedSMBConnection) async throws

    /// Retrieves stored authentication password for a saved server.
    func password(for server: SavedSMBConnection) async -> String?

    /// Checks active reachability status for a saved server.
    func checkServerStatus(_ server: SavedSMBConnection) async -> ServerConnectionStatus
}
