//
//  MediaSourceItem.swift
//  FichierKit
//
//

import Foundation

/// Canonical item model returned by any `MediaSource` implementation.
public struct MediaSourceItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let type: MediaItemType
    public let size: Int64
    public let modifiedDate: Date?
    public let localURL: URL?
    public let phAssetIdentifier: String?
    public let sourceID: String?
    public let smbShare: String?
    public let smbPath: String?

    public init(
        id: String,
        name: String,
        path: String,
        type: MediaItemType,
        size: Int64 = 0,
        modifiedDate: Date? = nil,
        localURL: URL? = nil,
        phAssetIdentifier: String? = nil,
        sourceID: String? = nil,
        smbShare: String? = nil,
        smbPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.type = type
        self.size = size
        self.modifiedDate = modifiedDate
        self.localURL = localURL
        self.phAssetIdentifier = phAssetIdentifier
        self.sourceID = sourceID
        self.smbShare = smbShare
        self.smbPath = smbPath
    }
}
