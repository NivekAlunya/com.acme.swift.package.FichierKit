//
//  SharesMediaSource.swift
//  FichierKit
//

import Foundation

/// Media source providing access to files and directories on a specific SMB server.
///
/// Returns shares as root folders when `folder == nil`, and directory contents within a mounted share.
/// Advertises `.list` layout and supports name, date, size, and type sorting.
public final class SharesMediaSource: MediaSource, Sendable {
    public let server: SavedSMBConnection
    public let client: any SMBClientProtocol

    public var id: String { server.id }
    public var displayName: String { server.displayName }
    public let preferredLayout: MediaSourceLayout = .list
    public let supportedSortKeys: Set<MediaSortKey> = [.name, .date, .size, .type]

    public init(server: SavedSMBConnection, client: any SMBClientProtocol) {
        self.server = server
        self.client = client
    }

    /// Fetches shares (when `folder == nil`) or directory contents on the server.
    public func fetchItems(
        in folder: MediaSourceItem?,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        page: Int,
        pageSize: Int
    ) async throws -> [MediaSourceItem] {
        if let folder {
            return try await loadDirectoryItems(
                in: folder,
                sortBy: sortKey,
                order: sortOrder,
                page: page,
                pageSize: pageSize
            )
        } else {
            return try await loadShares(
                sortBy: sortKey,
                order: sortOrder,
                page: page,
                pageSize: pageSize
            )
        }
    }

    // MARK: - Private Fetching Helpers

    private func loadShares(
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        page: Int,
        pageSize: Int
    ) async throws -> [MediaSourceItem] {
        let shareNames = try await client.listShares()
        let items: [MediaSourceItem] = shareNames.map { name in
            MediaSourceItem(
                id: "\(server.id)|\(name)::/",
                name: name,
                path: name,
                type: .folder,
                size: 0,
                modifiedDate: nil,
                sourceID: server.id,
                smbShare: name,
                smbPath: ""
            )
        }

        let sorted = items.sorted { lhs, rhs in
            let cmp = lhs.name.localizedStandardCompare(rhs.name)
            if cmp == .orderedSame {
                return sortOrder == .ascending ? lhs.id < rhs.id : lhs.id > rhs.id
            }
            return sortOrder == .ascending ? cmp == .orderedAscending : cmp == .orderedDescending
        }

        let startIndex = page * pageSize
        guard startIndex < sorted.count else { return [] }
        let endIndex = min(startIndex + pageSize, sorted.count)
        return Array(sorted[startIndex..<endIndex])
    }

    private func loadDirectoryItems(
        in folder: MediaSourceItem,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        page: Int,
        pageSize: Int
    ) async throws -> [MediaSourceItem] {
        let shareName: String
        let relativePath: String

        if let explicitShare = folder.smbShare {
            shareName = explicitShare
            relativePath = folder.smbPath ?? ""
        } else {
            let components = folder.path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            guard let shareNameSub = components.first else {
                return []
            }
            shareName = String(shareNameSub)
            relativePath = components.count > 1 ? String(components[1]) : ""
        }

        let directoryItems = try await client.listDirectory(share: shareName, path: relativePath).map { item in
            if item.sourceID != nil && item.smbShare != nil {
                return item
            }
            let itemRelativePath = item.smbPath ?? (relativePath.isEmpty ? item.name : "\(relativePath)/\(item.name)")
            return MediaSourceItem(
                id: item.id,
                name: item.name,
                path: item.path,
                type: item.type,
                size: item.size,
                modifiedDate: item.modifiedDate,
                localURL: item.localURL,
                phAssetIdentifier: item.phAssetIdentifier,
                sourceID: item.sourceID ?? server.id,
                smbShare: item.smbShare ?? shareName,
                smbPath: itemRelativePath
            )
        }

        // Separate folders from files so folders are always listed first (Section 4)
        var folders = directoryItems.filter { $0.type == .folder }
        var files = directoryItems.filter { $0.type != .folder }

        let comparator: (MediaSourceItem, MediaSourceItem) -> Bool = { lhs, rhs in
            let nameCompare = lhs.name.localizedStandardCompare(rhs.name)
            switch sortKey {
            case .name:
                if nameCompare == .orderedSame {
                    return sortOrder == .ascending ? lhs.id < rhs.id : lhs.id > rhs.id
                }
                return sortOrder == .ascending ? nameCompare == .orderedAscending : nameCompare == .orderedDescending
            case .date:
                let lDate = lhs.modifiedDate ?? .distantPast
                let rDate = rhs.modifiedDate ?? .distantPast
                if lDate == rDate {
                    return nameCompare == .orderedAscending
                }
                return sortOrder == .ascending ? lDate < rDate : lDate > rDate
            case .size:
                if lhs.size == rhs.size {
                    return nameCompare == .orderedAscending
                }
                return sortOrder == .ascending ? lhs.size < rhs.size : lhs.size > rhs.size
            case .type:
                let lExt = (lhs.name as NSString).pathExtension
                let rExt = (rhs.name as NSString).pathExtension
                let extCompare = lExt.localizedStandardCompare(rExt)
                if extCompare == .orderedSame {
                    return sortOrder == .ascending ? nameCompare == .orderedAscending : nameCompare == .orderedDescending
                }
                return sortOrder == .ascending ? extCompare == .orderedAscending : extCompare == .orderedDescending
            }
        }

        folders.sort(by: comparator)
        files.sort(by: comparator)

        let combined = folders + files
        let startIndex = page * pageSize
        guard startIndex < combined.count else { return [] }
        let endIndex = min(startIndex + pageSize, combined.count)
        return Array(combined[startIndex..<endIndex])
    }
}
