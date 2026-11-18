//
//  MediaSourceItem+FolderIcon.swift
//  FichierKit
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension MediaSourceItem {
    /// Cache coordinates (share, path, connection) used to hash a folder path for icon linking.
    var iconCacheCoordinates: (share: String, path: String, connectionID: String)? {
        guard phAssetIdentifier == nil else { return nil }
        if let smbShare, let smbPath {
            return (smbShare, smbPath, sourceID ?? "")
        }
        guard let sourceID else { return nil }
        return ("", path, sourceID)
    }

    #if canImport(UIKit)
    /// Links this item's thumbnail to its parent folder as the folder icon (images and videos only).
    public func linkThumbnailAsFolderIcon(_ image: UIImage) {
        guard type == .image || type == .video, let coords = iconCacheCoordinates else { return }
        MediaCacheManager.shared.linkFolderIcon(
            image,
            childPath: coords.path,
            shareName: coords.share,
            connectionID: coords.connectionID,
            isVideo: type == .video
        )
    }

    /// Loads the icon linked to this folder item, prioritizing images over videos.
    public func linkedFolderIcon() async -> UIImage? {
        guard type == .folder, let coords = iconCacheCoordinates else { return nil }
        return await MediaCacheManager.shared.folderIcon(
            folderPath: coords.path,
            shareName: coords.share,
            connectionID: coords.connectionID
        )
    }
    #endif
}
