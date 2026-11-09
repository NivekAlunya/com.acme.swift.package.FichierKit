//
//  MediaSourceResolverProtocol.swift
//  FichierKit
//
//

import Foundation

/// Defines an interface for resolving and invalidating a `MediaSource` instance by identifier.
public protocol MediaSourceResolverProtocol: Sendable {
    /// Resolves and returns the corresponding `MediaSource` for a source identifier.
    func resolve(sourceID: String) async -> (any MediaSource)?

    /// Invalidates a cached `MediaSource` (for example after editing or removing server credentials).
    func invalidateSource(id: String) async
}

public extension MediaSourceResolverProtocol {
    func invalidateSource(id: String) async {}
}
