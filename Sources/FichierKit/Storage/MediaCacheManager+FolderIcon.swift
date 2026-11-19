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

    private static let pathSlashSet = CharacterSet(charactersIn: "/")

    private static func normalizedFolderPath(_ path: String) -> String {
        path.trimmingCharacters(in: pathSlashSet)
    }

    #if canImport(UIKit)
    /// Links a child's thumbnail to its parent folder as the folder icon.
    ///
    /// Automatically downsamples full-resolution inputs to `standardThumbnailDimension` (420px)
    /// off the main thread before encoding to prevent disk bloat and memory spikes.
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
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let maxDim = max(image.size.width, image.size.height)
            let thumbnailToSave: UIImage
            if maxDim > Self.standardThumbnailDimension {
                let scale = Self.standardThumbnailDimension / maxDim
                let targetSize = CGSize(
                    width: max(1, (image.size.width * scale).rounded()),
                    height: max(1, (image.size.height * scale).rounded())
                )
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1.0
                let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
                thumbnailToSave = renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: targetSize))
                }
            } else {
                thumbnailToSave = image
            }
            await self.saveThumbnailAsync(thumbnailToSave, for: key)
        }
    }

    /// Loads the icon thumbnail linked to a folder, strictly prioritizing images over videos.
    ///
    /// Performs disk reads off the main thread to prevent scrolling hitches.
    ///
    /// - Parameters:
    ///   - folderPath: Full path of the folder.
    ///   - shareName: Storage root or share name.
    ///   - connectionID: Scoped connection identifier.
    /// - Returns: Image thumbnail if available, or `nil`.
    public func folderIcon(folderPath: String, shareName: String, connectionID: String = "") async -> UIImage? {
        let imageKey = folderIconKey(
            shareName: shareName,
            folderPath: folderPath,
            connectionID: connectionID,
            isVideo: false
        )
        let videoKey = folderIconKey(
            shareName: shareName,
            folderPath: folderPath,
            connectionID: connectionID,
            isVideo: true
        )
        let legacyKey = legacyFolderIconKey(
            shareName: shareName,
            folderPath: folderPath,
            connectionID: connectionID
        )

        return await Task.detached(priority: .userInitiated) { [weak self] () -> UIImage? in
            guard let self, !Task.isCancelled else { return nil }
            // Priority 1: Image thumbnail
            if let imageIcon = self.getThumbnail(for: imageKey) {
                return imageIcon
            }
            guard !Task.isCancelled else { return nil }
            // Priority 2: Video thumbnail
            if let videoIcon = self.getThumbnail(for: videoKey) {
                return videoIcon
            }
            guard !Task.isCancelled else { return nil }
            // Priority 3: Legacy fallback
            return self.getThumbnail(for: legacyKey)
        }.value
    }
    #endif
}
