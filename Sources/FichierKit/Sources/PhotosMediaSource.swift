//
//  PhotosMediaSource.swift
//  FichierKit
//

import Foundation
import Photos

/// Media source backed by the system PhotoKit library.
///
/// Returns albums as folders at the root level, and photos/videos within selected albums.
/// Advertises `.grid` layout and supports date and name sorting.
public final class PhotosMediaSource: MediaSource, Sendable {
    public let id: String = "photos"
    public let displayName: String = "Photos"
    public let preferredLayout: MediaSourceLayout = .grid
    public let supportedSortKeys: Set<MediaSortKey> = [.date, .name]

    public init() {}

    /// Current PhotoKit authorization status.
    public var authorizationStatus: PhotosAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .denied
        }
    }

    /// Prompts the user for PhotoKit access permissions.
    public func requestAuthorization() async -> PhotosAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .denied
        }
    }

    /// Fetches albums (when `folder == nil`) or assets within a chosen album.
    public func fetchItems(
        in folder: MediaSourceItem?,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        page: Int,
        pageSize: Int
    ) async throws -> [MediaSourceItem] {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw NSError(
                domain: "PhotosMediaSource",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Photos access is not authorized."]
            )
        }

        if let folder {
            return loadAssets(in: folder.path, sortBy: sortKey, order: sortOrder, page: page, pageSize: pageSize)
        } else {
            return loadAlbums(sortBy: sortKey, order: sortOrder, page: page, pageSize: pageSize)
        }
    }

    // MARK: - Private Enumeration Helpers

    private func loadAlbums(
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        page: Int,
        pageSize: Int
    ) -> [MediaSourceItem] {
        var albums: [MediaSourceItem] = []

        let smartSubtypes: [(PHAssetCollectionSubtype, String)] = [
            (.smartAlbumUserLibrary, "Recents"),
            (.smartAlbumFavorites, "Favorites"),
            (.smartAlbumVideos, "Videos"),
            (.smartAlbumScreenshots, "Screenshots")
        ]

        for (subtype, fallbackTitle) in smartSubtypes {
            let result = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            result.enumerateObjects { collection, _, _ in
                let count = collection.estimatedAssetCount != NSNotFound
                    ? collection.estimatedAssetCount
                    : PHAsset.fetchAssets(in: collection, options: nil).count

                if count > 0 || subtype == .smartAlbumUserLibrary {
                    let item = MediaSourceItem(
                        id: "album_\(collection.localIdentifier)",
                        name: collection.localizedTitle ?? fallbackTitle,
                        path: collection.localIdentifier,
                        type: .folder,
                        size: Int64(count),
                        modifiedDate: collection.startDate ?? collection.endDate
                    )
                    albums.append(item)
                }
            }
        }

        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let count = collection.estimatedAssetCount != NSNotFound
                ? collection.estimatedAssetCount
                : PHAsset.fetchAssets(in: collection, options: nil).count

            let item = MediaSourceItem(
                id: "album_\(collection.localIdentifier)",
                name: collection.localizedTitle ?? "Album",
                path: collection.localIdentifier,
                type: .folder,
                size: Int64(count),
                modifiedDate: collection.startDate ?? collection.endDate
            )
            albums.append(item)
        }

        let sorted = albums.sorted { lhs, rhs in
            switch sortKey {
            case .name:
                let cmp = lhs.name.localizedStandardCompare(rhs.name)
                if cmp == .orderedSame {
                    return sortOrder == .ascending ? lhs.id < rhs.id : lhs.id > rhs.id
                }
                return sortOrder == .ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            case .date:
                let lDate = lhs.modifiedDate ?? .distantPast
                let rDate = rhs.modifiedDate ?? .distantPast
                if lDate == rDate {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return sortOrder == .ascending ? lDate < rDate : lDate > rDate
            default:
                let cmp = lhs.name.localizedStandardCompare(rhs.name)
                return sortOrder == .ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }

        let startIndex = page * pageSize
        guard startIndex < sorted.count else { return [] }
        let endIndex = min(startIndex + pageSize, sorted.count)
        return Array(sorted[startIndex..<endIndex])
    }

    private func loadAssets(
        in collectionIdentifier: String,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        page: Int,
        pageSize: Int
    ) -> [MediaSourceItem] {
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [collectionIdentifier], options: nil)
        guard let collection = collections.firstObject else { return [] }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d || mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        let isAscending = sortOrder == .ascending

        if sortKey == .date {
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: isAscending)]
            let fetchResult = PHAsset.fetchAssets(in: collection, options: options)
            let totalCount = fetchResult.count
            let startIndex = page * pageSize
            guard startIndex < totalCount else { return [] }
            let endIndex = min(startIndex + pageSize, totalCount)

            var items: [MediaSourceItem] = []
            items.reserveCapacity(endIndex - startIndex)
            for index in startIndex..<endIndex {
                let asset = fetchResult.object(at: index)
                items.append(makeMediaSourceItem(for: asset, fileName: Self.resolveAssetFileName(asset)))
            }
            return items
        }

        // PhotoKit rejects `filename` in PHFetchOptions.sortDescriptors, so fetch and sort by resolved filename in memory.
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(in: collection, options: options)
        let totalCount = fetchResult.count
        guard totalCount > 0 else { return [] }

        var namedAssets: [(asset: PHAsset, fileName: String)] = []
        namedAssets.reserveCapacity(totalCount)
        fetchResult.enumerateObjects { asset, _, _ in
            namedAssets.append((asset, Self.resolveAssetFileName(asset)))
        }

        namedAssets.sort { lhs, rhs in
            let cmp = lhs.fileName.localizedStandardCompare(rhs.fileName)
            if cmp == .orderedSame {
                return isAscending
                    ? lhs.asset.localIdentifier < rhs.asset.localIdentifier
                    : lhs.asset.localIdentifier > rhs.asset.localIdentifier
            }
            return isAscending ? cmp == .orderedAscending : cmp == .orderedDescending
        }

        let startIndex = page * pageSize
        guard startIndex < namedAssets.count else { return [] }
        let endIndex = min(startIndex + pageSize, namedAssets.count)

        return namedAssets[startIndex..<endIndex].map { entry in
            makeMediaSourceItem(for: entry.asset, fileName: entry.fileName)
        }
    }

    private func makeMediaSourceItem(for asset: PHAsset, fileName: String) -> MediaSourceItem {
        let isVideo = asset.mediaType == .video
        let estimatedSize = Int64(asset.pixelWidth * asset.pixelHeight * (isVideo ? 1 : 4))
        return MediaSourceItem(
            id: "ph_\(asset.localIdentifier)",
            name: fileName,
            path: asset.localIdentifier,
            type: isVideo ? .video : .image,
            size: estimatedSize,
            modifiedDate: asset.creationDate,
            phAssetIdentifier: asset.localIdentifier
        )
    }

    private static func resolveAssetFileName(_ asset: PHAsset) -> String {
        let isVideo = asset.mediaType == .video
        let ext = isVideo ? "mov" : "jpg"
        let defaultName = "IMG_\(asset.localIdentifier.prefix(8)).\(ext)"
        return (asset.value(forKey: "filename") as? String) ?? defaultName
    }
}
