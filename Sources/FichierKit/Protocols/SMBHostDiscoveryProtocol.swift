//
//  SMBHostDiscoveryProtocol.swift
//  FichierKit
//
//

import Foundation

/// Protocol abstracting Bonjour/mDNS local network discovery for SMB servers.
@MainActor
public protocol SMBHostDiscoveryProtocol: AnyObject {
    var discoveredHosts: [DiscoveredHost] { get }
    var isScanning: Bool { get }
    var errorMessage: String? { get }

    func startDiscovery()
    func stopDiscovery()
}
