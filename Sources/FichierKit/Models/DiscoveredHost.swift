//
//  DiscoveredHost.swift
//  FichierKit
//
//

import Foundation
import Network

/// Represents a Bonjour-advertised SMB server discovered on the local area network (`_smb._tcp`).
public struct DiscoveredHost: Identifiable, Hashable, Sendable {
    /// Stable identifier preserving SwiftUI and tvOS focus across asynchronous IPv4 resolution updates.
    public var id: String { name }

    /// User-friendly advertised Bonjour service name (e.g. `"Mac mini"`).
    public let name: String

    /// Resolved IPv4 address string or hostname, or `nil` while DNS resolution is in progress.
    public var resolvedHost: String?

    /// Underlying Network endpoint used by `NWConnection` to resolve IP connectivity.
    public let endpoint: NWEndpoint?

    public init(name: String, resolvedHost: String? = nil, endpoint: NWEndpoint? = nil) {
        self.name = name
        self.resolvedHost = resolvedHost
        self.endpoint = endpoint
    }
}
