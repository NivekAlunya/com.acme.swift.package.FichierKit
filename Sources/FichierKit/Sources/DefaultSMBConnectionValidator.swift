//
//  DefaultSMBConnectionValidator.swift
//  FichierKit
//
//

import Foundation

/// Default `SMBConnectionValidatorProtocol` implementation backed by `AMSMB2Client`.
public struct DefaultSMBConnectionValidator: SMBConnectionValidatorProtocol {
    public static let shared = DefaultSMBConnectionValidator()

    public init() {}

    public func validateAndListShares(for server: SavedSMBConnection, password: String) async throws -> [String] {
        let cleanHost = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHost.isEmpty || (cleanHost.contains(":") && !cleanHost.hasPrefix("[")) {
            throw SMBError.unknown("Enter a valid host address or IP without a port suffix.")
        }

        let client = AMSMB2Client(server: server, password: password)
        do {
            let shares = try await client.listShares()
            await client.disconnect()
            guard !shares.isEmpty else {
                throw SMBError.noShares
            }
            return shares
        } catch {
            await client.disconnect()
            throw error
        }
    }
}
