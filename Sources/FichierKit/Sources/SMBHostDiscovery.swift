//
//  SMBHostDiscovery.swift
//  FichierKit
//
//

import Foundation
import Network
import Observation
import OSLog

/// Locates SMB servers on the local area network using Bonjour (`_smb._tcp`) and resolves IPv4 addresses.
///
/// Mirrors the iOS `SMBHostDiscovery` workflow while maintaining stable tvOS focus identifiers
/// and strict Swift 6 concurrency isolation.
@Observable
@MainActor
public final class SMBHostDiscovery: SMBHostDiscoveryProtocol {
    public private(set) var discoveredHosts: [DiscoveredHost] = []
    public private(set) var isScanning: Bool = false
    public private(set) var errorMessage: String?

    private var browser: NWBrowser?
    private var pendingConnections: [String: NWConnection] = [:]

    private let logger = Logger(subsystem: "com.acme.ios.fichierkit", category: "discovery")

    public init() {}

    /// Begins scanning the local network for Bonjour SMB advertisements (`_smb._tcp` in `local.`).
    public func startDiscovery() {
        stopDiscovery()
        discoveredHosts = []
        isScanning = true
        errorMessage = nil

        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        if let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_smb._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: parameters)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.browser === browser else { return }
                switch state {
                case .ready:
                    self.errorMessage = nil
                    self.logger.info("SMB Bonjour browser active (IPv4)")
                case .waiting(let error):
                    self.logger.warning("SMB Bonjour browser waiting: \(error.localizedDescription)")
                    self.errorMessage = "Waiting for local network access: \(error.localizedDescription)"
                case .failed(let error):
                    self.logger.error("SMB Bonjour scan failed: \(error.localizedDescription)")
                    self.errorMessage = "Network discovery failed: \(error.localizedDescription)"
                    self.isScanning = false
                case .cancelled:
                    self.isScanning = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self, self.browser === browser else { return }
                self.handleBrowseResults(results)
            }
        }

        // Network.framework's NWBrowser C/ObjC callback API requires a DispatchQueue.
        browser.start(queue: .main)
    }

    /// Stops the active Bonjour scan and cancels any in-flight IPv4 resolution connections.
    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
        for connection in pendingConnections.values {
            connection.cancel()
        }
        pendingConnections.removeAll()
        isScanning = false
    }

    // MARK: - Private Resolution

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        let existingResolvedByName = Dictionary(
            uniqueKeysWithValues: discoveredHosts.compactMap { host in
                host.resolvedHost.map { (host.name, $0) }
            }
        )

        var hostsByName: [String: DiscoveredHost] = [:]
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            guard hostsByName[name] == nil else { continue }

            let existingResolved = existingResolvedByName[name]
            let host = DiscoveredHost(
                name: name,
                resolvedHost: existingResolved,
                endpoint: result.endpoint
            )
            hostsByName[name] = host
        }

        let activeNames = Set(hostsByName.keys)
        for (name, connection) in pendingConnections where !activeNames.contains(name) {
            connection.cancel()
            pendingConnections.removeValue(forKey: name)
        }

        discoveredHosts = hostsByName.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        for host in discoveredHosts where host.resolvedHost == nil && pendingConnections[host.name] == nil {
            resolveIPv4Host(for: host)
        }
    }

    private func resolveIPv4Host(for host: DiscoveredHost) {
        guard let endpoint = host.endpoint else { return }

        let tcpParams = NWParameters.tcp
        if let ipOptions = tcpParams.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }

        let connection = NWConnection(to: endpoint, using: tcpParams)
        pendingConnections[host.name] = connection
        let hostName = host.name

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                guard self.pendingConnections[hostName] === connection else { return }

                switch state {
                case .ready:
                    if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                       case let .hostPort(resolvedHost, _) = innerEndpoint {
                        let ipv4String: String?
                        switch resolvedHost {
                        case .ipv4(let ip):
                            let raw = "\(ip)"
                            ipv4String = raw.components(separatedBy: "%").first ?? raw
                        case .name(let hostname, _):
                            ipv4String = hostname
                        case .ipv6:
                            ipv4String = nil
                        @unknown default:
                            ipv4String = nil
                        }

                        if let validHost = ipv4String, !validHost.isEmpty {
                            self.updateResolvedHost(for: hostName, resolvedHost: validHost)
                        }
                    }
                    self.pendingConnections.removeValue(forKey: hostName)
                    connection.cancel()
                case .failed, .cancelled:
                    self.pendingConnections.removeValue(forKey: hostName)
                    connection.cancel()
                default:
                    break
                }
            }
        }

        // Network.framework's NWConnection C/ObjC callback API requires a DispatchQueue.
        connection.start(queue: .main)
    }

    private func updateResolvedHost(for name: String, resolvedHost: String) {
        if let index = discoveredHosts.firstIndex(where: { $0.name == name }) {
            discoveredHosts[index].resolvedHost = resolvedHost
        }
    }
}
