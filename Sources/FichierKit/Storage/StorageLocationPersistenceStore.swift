//
//  StorageLocationPersistenceStore.swift
//  FichierKit
//

import Foundation
import Wappn

/// Persistence manager responsible for storing and loading user connections and sandboxed bookmarks.
///
/// Encapsulates access to `UserDefaults` for SMB server connection metadata and local/iCloud Drive
/// security-scoped folder bookmarks, as well as `SMBPasswordStore` for secure credential storage.
@MainActor
public final class StorageLocationPersistenceStore {

    /// Key for persisted SMB connections in `UserDefaults`.
    private let savedConnectionsKey = "SavedSMBServerConnections_v2"

    /// Key for persisted local and iCloud Drive folder bookmarks in `UserDefaults`.
    private let savedFolderLocationsKey = "SavedFolderLocations_v1"

    /// Shared user defaults instance.
    private let userDefaults: UserDefaults

    /// Secure Keychain store from `FichierKit`.
    private let passwordStore: SMBPasswordStore

    /// Initializes a new persistence store with the given defaults instance and password store.
    ///
    /// - Parameters:
    ///   - userDefaults: Target `UserDefaults` backing store (defaults to `.standard`).
    ///   - passwordStore: Target `SMBPasswordStore` (defaults to `.shared`).
    public init(
        userDefaults: UserDefaults = .standard,
        passwordStore: SMBPasswordStore = .shared
    ) {
        self.userDefaults = userDefaults
        self.passwordStore = passwordStore
    }

    // MARK: - SMB Connections Persistence

    /// Loads and decodes persisted SMB connections from `UserDefaults`.
    ///
    /// - Returns: An array of `SavedSMBConnection` sorted with most recent connections first.
    public func loadSavedConnections() -> [SavedSMBConnection] {
        guard let data = userDefaults.data(forKey: savedConnectionsKey) else {
            return []
        }
        do {
            let decoded = try JSONDecoder().decode([SavedSMBConnection].self, from: data)
            return decoded.sorted { $0.lastConnected > $1.lastConnected }
        } catch {
            loge("Failed to decode saved SMB connections: \(error.localizedDescription)")
            return []
        }
    }

    /// Retrieves the stored password from the secure Keychain for a given SMB connection.
    ///
    /// - Parameter connection: The saved connection metadata.
    /// - Returns: The decrypted password, or an empty string if missing.
    public func password(for connection: SavedSMBConnection) async -> String {
        await passwordStore.loadPassword(for: connection.id) ?? ""
    }

    /// Stores or updates a validated SMB connection record and saves its password to the Keychain.
    ///
    /// - Parameters:
    ///   - host: Network hostname or IP address.
    ///   - user: Authentication username.
    ///   - pass: Plaintext password to store in Keychain.
    ///   - hostname: Optional Bonjour or NetBIOS display hostname.
    ///   - existingConnections: Current list of saved connections.
    /// - Returns: The updated list of saved connections.
    public func saveValidatedConnection(
        host: String,
        user: String,
        pass: String,
        hostname: String? = nil,
        existingConnections: [SavedSMBConnection]
    ) async -> [SavedSMBConnection] {
        let existingHostname = existingConnections.first(where: { $0.id == "\(user)@\(host)" })?.hostname
        let finalHostname = hostname ?? existingHostname

        let newEntry = SavedSMBConnection(
            host: host,
            username: user,
            lastConnected: Date(),
            hostname: finalHostname
        )
        await passwordStore.savePassword(pass, for: newEntry.id)

        var updated = existingConnections.filter { $0.id != newEntry.id }
        updated.insert(newEntry, at: 0)

        persistConnections(updated)
        return updated
    }

    /// Deletes a saved connection record from `UserDefaults` and removes its password from Keychain.
    ///
    /// - Parameters:
    ///   - connection: The connection to remove.
    ///   - existingConnections: Current list of saved connections.
    /// - Returns: The updated list of saved connections.
    public func removeSavedConnection(
        _ connection: SavedSMBConnection,
        from existingConnections: [SavedSMBConnection]
    ) async -> [SavedSMBConnection] {
        await passwordStore.deletePassword(for: connection.id)
        var updated = existingConnections
        updated.removeAll { $0.id == connection.id }
        persistConnections(updated)
        return updated
    }

    /// Serializes and writes SMB connection records to `UserDefaults`.
    private func persistConnections(_ connections: [SavedSMBConnection]) {
        do {
            let encoded = try JSONEncoder().encode(connections)
            userDefaults.set(encoded, forKey: savedConnectionsKey)
        } catch {
            loge("Failed to encode and persist SMB connections: \(error.localizedDescription)")
        }
    }

    // MARK: - Folder Locations Persistence (Local & iCloud Drive)

    /// Loads and decodes local folder bookmarks from `UserDefaults`.
    ///
    /// - Returns: An array of `SavedFolderLocation` sorted by addition date descending.
    public func loadSavedFolderLocations() -> [SavedFolderLocation] {
        guard let data = userDefaults.data(forKey: savedFolderLocationsKey) else {
            return []
        }
        do {
            let decoded = try JSONDecoder().decode([SavedFolderLocation].self, from: data)
            return decoded.sorted { $0.dateAdded > $1.dateAdded }
        } catch {
            loge("Failed to decode saved folder locations: \(error.localizedDescription)")
            return []
        }
    }

    /// Appends or updates a saved local folder location and persists it to `UserDefaults`.
    ///
    /// - Parameters:
    ///   - location: The folder location record containing security-scoped bookmark data.
    ///   - existingLocations: Current list of folder locations.
    /// - Returns: The updated list of folder locations.
    public func addSavedFolderLocation(
        _ location: SavedFolderLocation,
        into existingLocations: [SavedFolderLocation]
    ) -> [SavedFolderLocation] {
        var updated = existingLocations.filter { $0.id != location.id }
        updated.insert(location, at: 0)
        persistFolderLocations(updated)
        return updated
    }

    /// Removes a saved local folder location from `UserDefaults`.
    ///
    /// - Parameters:
    ///   - location: The folder location to remove.
    ///   - existingLocations: Current list of folder locations.
    /// - Returns: The updated list of folder locations.
    public func removeSavedFolderLocation(
        _ location: SavedFolderLocation,
        from existingLocations: [SavedFolderLocation]
    ) -> [SavedFolderLocation] {
        var updated = existingLocations
        updated.removeAll { $0.id == location.id }
        persistFolderLocations(updated)
        return updated
    }

    /// Updates refreshed security-scoped bookmark data for an existing folder location.
    ///
    /// - Parameters:
    ///   - bookmarkData: The updated binary bookmark data.
    ///   - folderLocation: The target location record.
    ///   - existingLocations: Current list of folder locations.
    /// - Returns: The updated list of folder locations.
    public func updateBookmarkData(
        _ bookmarkData: Data,
        for folderLocation: SavedFolderLocation,
        in existingLocations: [SavedFolderLocation]
    ) -> [SavedFolderLocation] {
        guard let index = existingLocations.firstIndex(where: { $0.id == folderLocation.id }) else {
            return existingLocations
        }
        var updated = existingLocations
        updated[index] = SavedFolderLocation(
            id: folderLocation.id,
            name: folderLocation.name,
            bookmarkData: bookmarkData,
            isICloud: folderLocation.isICloud,
            dateAdded: folderLocation.dateAdded
        )
        persistFolderLocations(updated)
        return updated
    }

    /// Serializes and writes folder location records to `UserDefaults`.
    private func persistFolderLocations(_ locations: [SavedFolderLocation]) {
        do {
            let encoded = try JSONEncoder().encode(locations)
            userDefaults.set(encoded, forKey: savedFolderLocationsKey)
        } catch {
            loge("Failed to encode and persist folder locations: \(error.localizedDescription)")
        }
    }
}
