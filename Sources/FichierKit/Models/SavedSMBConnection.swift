//
//  SavedSMBConnection.swift
//  FichierKit
//

import Foundation
import os

/// Persisted configuration record representing a saved SMB server connection.
public struct SavedSMBConnection: Identifiable, Codable, Hashable, Sendable {
    private static let logger = Logger(subsystem: "com.acme.ios.fichierkit", category: "savedSMBConnection")
    public var id: String { "\(username)@\(host)" }
    public let host: String
    public let username: String
    public let lastConnected: Date
    public let hostname: String?

    public init(
        host: String,
        username: String,
        lastConnected: Date,
        hostname: String? = nil
    ) {
        self.host = host
        self.username = username
        self.lastConnected = lastConnected
        self.hostname = hostname
    }

    public var displayName: String {
        if let hostname = hostname?.trimmingCharacters(in: .whitespacesAndNewlines), !hostname.isEmpty, hostname != host {
            return "\(hostname) [\(host)]"
        } else {
            return host
        }
    }

    /// Standard UserDefaults storage key for persisted SMB server connections.
    public static let storageKey = "SavedSMBServerConnections_v2"

    /// Decodes a list of saved SMB connections from binary JSON data, sorted by `lastConnected` descending.
    public static func decodeList(from data: Data?) -> [SavedSMBConnection] {
        guard let data else { return [] }
        do {
            let decoded = try JSONDecoder().decode([SavedSMBConnection].self, from: data)
            return decoded.sorted { $0.lastConnected > $1.lastConnected }
        } catch {
            logger.error("Failed to decode saved SMB connections: \(error.localizedDescription)")
            return []
        }
    }

    /// Encodes a list of saved SMB connections to binary JSON data.
    public static func encodeList(_ connections: [SavedSMBConnection]) throws -> Data {
        try JSONEncoder().encode(connections)
    }
}
