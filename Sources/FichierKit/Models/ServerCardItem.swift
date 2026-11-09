//
//  ServerCardItem.swift
//  FichierKit
//

import Foundation

/// Display model for an SMB server card on tvOS.
public struct ServerCardItem: Identifiable, Hashable, Sendable {
    public let connection: SavedSMBConnection
    public let status: ServerConnectionStatus

    public var id: String { connection.id }
    public var name: String { connection.displayName }
    public var host: String { connection.host }

    public init(connection: SavedSMBConnection, status: ServerConnectionStatus = .unknown) {
        self.connection = connection
        self.status = status
    }
}
