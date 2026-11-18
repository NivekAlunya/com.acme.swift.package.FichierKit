//
//  MediaCacheManager+FolderIcon.swift
//  FichierKit
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Folder icon support: a folder is linked to a thumbnail through the hash of its full path.
///
/// Images are strictly prioritized over videos:
/// 1. If an image thumbnail exists (generated with no cache hit or last viewed), it is used.
/// 2. If no image exists, the last video thumbnail (generated with no cache hit or last played) is used.
extension MediaCacheManager {
    /// Computes the cache key linking a folder (by full path) to its icon thumbnail.
    ///
    /// - Parameters:
    ///   - shareName: Storage root or share name.
    ///   - folderPath: Full path of the folder.
    ///   - connectionID: Scoped connection identifier.
    ///   - isVideo: Whether this key represents a video (`true`) or image (`false`) thumbnail.
    public func folderIconKey(
        shareName: String,
        folderPath: String,
        connectionID: String = "",
        isVideo: Bool = false
    ) -> String {
        let normalized = Self.normalizedFolderPath(folderPath)
        let kind = isVideo ? "vid" : "img"
        return cacheKey(
            for: shareName,
            path: "\(normalized)_foldericon_\(kind)_v2",
            dimension: Self.standardThumbnailDimension,
            connectionID: connectionID
        )
    }

    /// Legacy single-slot folder icon key for migration.
    public func legacyFolderIconKey(shareName: String, folderPath: String, connectionID: String = "") -> String {
        let normalized = Self.normalizedFolderPath(folderPath)
        return cacheKey(
            for: shareName,
            path: "\(normalized)_foldericon_v1",
            dimension: Self.standardThumbnailDimension,
            connectionID: connectionID
        )
    }

    /// Returns the parent folder path of an item path (empty string for root-level items).
    public static func parentFolderPath(of itemPath: String) -> String {
        let normalized = normalizedFolderPath(itemPath)
        guard let slash = normalized.lastIndex(of: "/") else { return "" }
        return String(normalized[..<slash])
    }

    private static func normalizedFolderPath(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    #if canImport(UIKit)
    /// Links a child's thumbnail to its parent folder as the folder icon.
    ///
    /// - Parameters:
    ///   - image: Thumbnail of a direct child (image or video).
    ///   - childPath: Full path of the child item.
    ///   - shareName: Storage root or share name.
    ///   - connectionID: Scoped connection identifier.
    ///   - isVideo: Whether the source item is a video (`true`) or an image (`false`).
    public func linkFolderIcon(
        _ image: UIImage,
        childPath: String,
        shareName: String,
        connectionID: String = "",
        isVideo: Bool = false
    ) {
        let parentFolder = Self.parentFolderPath(of: childPath)
        let key = folderIconKey(
            shareName: shareName,
            folderPath: parentFolder,
            connectionID: connectionID,
            isVideo: isVideo
        )
        saveThumbnailAsync(image, for: key)
    }

    /// Loads the icon thumbnail linked to a folder, strictly prioritizing images over videos.
    ///
    /// - Parameters:
    ///   - folderPath: Full path of the folder.
    ///   - shareName: Storage root or share name.
    ///   - connectionID: Scoped connection identifier.
    /// - Returns: Image thumbnail if available, or `nil`.
    public func folderIcon(folderPath: String, shareName: String, connectionID: String = "") async -> UIImage? {
        // Priority 1: Image thumbnail
        let imageKey = folderIconKey(shareName: shareName, folderPath: folderPath, connectionID: connectionID, isVideo: false)
        if let imageIcon = await getThumbnailAsync(for: imageKey) {
            return imageIcon
        }

        // Priority 2: Video thumbnail
        let videoKey = folderIconKey(shareName: shareName, folderPath: folderPath, connectionID: connectionID, isVideo: true)
        if let videoIcon = await getThumbnailAsync(for: videoKey) {
            return videoIcon
        }

        // Priority 3: Legacy fallback
        let legacyKey = legacyFolderIconKey(shareName: shareName, folderPath: folderPath, connectionID: connectionID)
        return await getThumbnailAsync(for: legacyKey)
    }
    #endif
}
