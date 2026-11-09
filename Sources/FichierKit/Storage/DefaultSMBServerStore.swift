//
//  DefaultSMBServerStore.swift
//  FichierKit
//
//

import Foundation
import Network

/// Actor-isolated store persisting SMB connections in `UserDefaults`, passwords in Keychain, and testing reachability.
public actor DefaultSMBServerStore: SMBServerStoreProtocol {
    public static let shared = DefaultSMBServerStore()

    private let userDefaults: UserDefaults
    private let passwordStore: SMBPasswordStore
    private let savedConnectionsKey = "SavedSMBServerConnections_v2"

    public init(
        userDefaults: UserDefaults = .standard,
        passwordStore: SMBPasswordStore = .shared
    ) {
        self.userDefaults = userDefaults
        self.passwordStore = passwordStore
    }

    /// Loads and decodes saved connections sorted with most recently connected first.
    public func loadServers() async -> [SavedSMBConnection] {
        guard let data = userDefaults.data(forKey: savedConnectionsKey) else {
            return []
        }
        do {
            let decoded = try JSONDecoder().decode([SavedSMBConnection].self, from: data)
            return decoded.sorted { $0.lastConnected > $1.lastConnected }
        } catch {
            return []
        }
    }

    /// Stores or updates an SMB connection record and persists its password cleanly.
    public func saveServer(_ server: SavedSMBConnection, password: String) async throws {
        var existing = await loadServers()
        await passwordStore.savePassword(password, for: server.id)

        existing.removeAll { $0.id == server.id }
        existing.insert(server, at: 0)

        let data = try JSONEncoder().encode(existing)
        userDefaults.set(data, forKey: savedConnectionsKey)
    }

    /// Removes a saved connection from persistence and clears its credential.
    public func removeServer(_ server: SavedSMBConnection) async throws {
        var existing = await loadServers()
        await passwordStore.deletePassword(for: server.id)

        existing.removeAll { $0.id == server.id }

        let data = try JSONEncoder().encode(existing)
        userDefaults.set(data, forKey: savedConnectionsKey)
    }

    /// Retrieves the stored password for a given server.
    public func password(for server: SavedSMBConnection) async -> String? {
        await passwordStore.loadPassword(for: server.id)
    }

    /// Checks server reachability over the standard SMB TCP port (445).
    public func checkServerStatus(_ server: SavedSMBConnection) async -> ServerConnectionStatus {
        let host = NWEndpoint.Host(server.host)
        let port = NWEndpoint.Port(integerLiteral: 445)
        let connection = NWConnection(host: host, port: port, using: .tcp)

        let states = AsyncStream<NWConnection.State> { continuation in
            connection.stateUpdateHandler = { state in
                continuation.yield(state)
                switch state {
                case .ready, .failed, .cancelled:
                    continuation.finish()
                default:
                    break
                }
            }
            continuation.onTermination = { _ in
                connection.cancel()
            }
            connection.start(queue: .global())
        }

        do {
            return try await withThrowingTaskGroup(of: ServerConnectionStatus.self) { group in
                group.addTask {
                    for await state in states {
                        switch state {
                        case .ready:
                            return .online
                        case .failed, .cancelled:
                            return .offline
                        default:
                            break
                        }
                    }
                    return .offline
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                    return .offline
                }

                let result = try await group.next() ?? .offline
                group.cancelAll()
                return result
            }
        } catch {
            return .offline
        }
    }
}
