//
//  ServerConnectionStatus.swift
//  FichierKit
//

import Foundation

/// Operational reachability state of a saved SMB server.
public enum ServerConnectionStatus: String, Sendable, Hashable, Equatable {
    case online = "Online"
    case offline = "Offline"
    case connecting = "Connecting"
    case unknown = "Unknown"
}
