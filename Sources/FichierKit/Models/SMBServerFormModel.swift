//
//  SMBServerFormModel.swift
//  FichierKit
//

import Foundation

/// Form state model managing SMB server configuration inputs, validation, and serialization.
public struct SMBServerFormModel: Sendable, Equatable {
    public var hostname: String = ""
    public var host: String = ""
    public var username: String = ""
    public var password: String = ""
    public var isSaving: Bool = false
    public var errorMessage: String?

    public var normalizedHost: String {
        var cleaned = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("smb://") {
            cleaned = String(cleaned.dropFirst(6))
        }
        if let slashIndex = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[..<slashIndex])
        }
        if let percentIndex = cleaned.firstIndex(of: "%") {
            cleaned = String(cleaned[..<percentIndex])
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValid: Bool {
        !normalizedHost.isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init() {}

    /// Pre-populates the form with details from an existing server connection.
    public mutating func populate(from server: SavedSMBConnection, existingPassword: String = "") {
        self.hostname = server.hostname ?? ""
        self.host = server.host
        self.username = server.username
        self.password = existingPassword
        self.errorMessage = nil
    }

    /// Builds a `SavedSMBConnection` value from current inputs.
    public func makeConnection() -> SavedSMBConnection {
        let cleanHost = normalizedHost
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)

        return SavedSMBConnection(
            host: cleanHost,
            username: trimmedUser,
            lastConnected: Date(),
            hostname: trimmedHostname.isEmpty ? nil : trimmedHostname
        )
    }
}
