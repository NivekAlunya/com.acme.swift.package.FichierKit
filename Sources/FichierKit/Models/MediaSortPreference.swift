//
//  MediaSortPreference.swift
//  FichierKit
//

import Foundation

/// Persisted sort key and order preference for a specific media source.
public struct MediaSortPreference: Sendable, Codable, Equatable {
    public let key: MediaSortKey
    public let order: MediaSortOrder

    public init(key: MediaSortKey, order: MediaSortOrder) {
        self.key = key
        self.order = order
    }
}
