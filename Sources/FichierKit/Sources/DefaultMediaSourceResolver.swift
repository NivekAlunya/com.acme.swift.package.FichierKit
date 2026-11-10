//
//  DefaultMediaSourceResolver.swift
//  FichierKit
//
//

import Foundation

/// Default implementation of `MediaSourceResolverProtocol` resolving Photos and registered or saved SMB shares.
public actor DefaultMediaSourceResolver: MediaSourceResolverProtocol {
    public static let shared = DefaultMediaSourceResolver()

    private var registeredSources: [String: any MediaSource] = [:]
    private let serverStore: any SMBServerStoreProtocol

    public init(serverStore: any SMBServerStoreProtocol = DefaultSMBServerStore.shared) {
        self.serverStore = serverStore
        let photos = PhotosMediaSource()
        registeredSources[photos.id] = photos
    }

    /// Registers a custom or dynamically constructed media source.
    public func register(source: any MediaSource) {
        registeredSources[source.id] = source
    }

    /// Invalidates a cached source (e.g. after server credentials or details are edited or removed).
    public func invalidateSource(id: String) async {
        if let sharesSource = registeredSources.removeValue(forKey: id) as? SharesMediaSource {
            await sharesSource.client.disconnect()
        }
    }

    /// Resolves and returns the corresponding `MediaSource` for the specified source identifier.
    public func resolve(sourceID: String) async -> (any MediaSource)? {
        if let existing = registeredSources[sourceID] {
            return existing
        }
        if sourceID == "photos" {
            let photos = PhotosMediaSource()
            registeredSources[photos.id] = photos
            return photos
        }

        let servers = await serverStore.loadServers()
        guard let server = servers.first(where: { $0.id == sourceID }) else {
            return nil
        }

        let password = await serverStore.password(for: server) ?? ""

        // Check again across actor suspension boundaries
        if let existing = registeredSources[sourceID] {
            return existing
        }

        let client = AMSMB2Client(server: server, password: password)
        let sharesSource = SharesMediaSource(server: server, client: client)
        registeredSources[sourceID] = sharesSource
        return sharesSource
    }

    /// Resolves and returns the underlying SMB client for the specified SMB source identifier, if available.
    public func smbClient(for sourceID: String) async -> (any SMBClientProtocol)? {
        let source = await resolve(sourceID: sourceID)
        return (source as? SharesMediaSource)?.client
    }
}
