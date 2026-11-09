//
//  SavedSMBConnection.swift
//  FichierKit
//

import Foundation

/// Persisted configuration record representing a saved SMB server connection.
public struct SavedSMBConnection: Identifiable, Codable, Hashable, Sendable {
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
}
