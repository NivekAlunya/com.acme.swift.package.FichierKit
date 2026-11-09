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

    private let cursorStore = SharesCursorStore()

    public init(server: SavedSMBConnection, client: any SMBClientProtocol) {
        self.server = server
        self.client = client
    }

    /// Fetches shares (when `folder == nil`) or directory contents on the server using indexed pagination.
    public func fetchItems(
        in folder: MediaSourceItem?,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        page: Int,
        pageSize: Int
    ) async throws -> [MediaSourceItem] {
        try Task.checkCancellation()
        guard page >= 0, pageSize > 0 else { return [] }

        let scopeKey = "\(folder?.id ?? "__shares__")|\(sortKey.rawValue)|\(sortOrder.rawValue)"
        if page == 0 {
            await cursorStore.resetScope(scopeKey)
        }

        let cursorLookup = await cursorStore.cursor(forPage: page, scopeKey: scopeKey, pageSize: pageSize)
        if cursorLookup.shouldSkipFetch {
            return []
        }

        let directoryPage = try await fetchDirectoryPage(
            in: folder,
            sortBy: sortKey,
            order: sortOrder,
            cursor: cursorLookup.cursor,
            pageSize: pageSize
        )
        try Task.checkCancellation()
        await cursorStore.record(nextCursor: directoryPage.nextCursor, afterPage: page, forScope: scopeKey)
        return directoryPage.items
    }

    /// Fetches a bounded cursor-addressed page of shares or directory contents without materializing trailing pages.
    ///
    /// - Parameters:
    ///   - folder: Target folder item, or `nil` for root SMB shares.
    ///   - sortKey: Explicit sort attribute.
    ///   - sortOrder: Sort direction.
    ///   - cursor: Opaque continuation cursor from a previous `SMBDirectoryPage`, or `nil` for the first page.
    ///   - pageSize: Maximum number of items to return.
    /// - Returns: A bounded `SMBDirectoryPage` preserving folder-first order and media classification.
    public func fetchDirectoryPage(
        in folder: MediaSourceItem?,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        cursor: String?,
        pageSize: Int
    ) async throws -> SMBDirectoryPage {
        try Task.checkCancellation()
        guard pageSize > 0 else {
            return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: nil)
        }

        if let folder {
            return try await loadDirectoryPage(
                in: folder,
                sortBy: sortKey,
                order: sortOrder,
                cursor: cursor,
                pageSize: pageSize
            )
        } else {
            return try await loadSharesPage(
                order: sortOrder,
                cursor: cursor,
                pageSize: pageSize
            )
        }
    }

    // MARK: - Private Fetching Helpers

    private func loadSharesPage(
        order sortOrder: MediaSortOrder,
        cursor: String?,
        pageSize: Int
    ) async throws -> SMBDirectoryPage {
        let offset: Int
        if let cursor {
            guard let parsedOffset = Int(cursor), parsedOffset >= 0 else {
                return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: nil)
            }
            offset = parsedOffset
        } else {
            offset = 0
        }

        let shareNames = try await client.listShares()
        try Task.checkCancellation()

        // Sort raw share names before mapping to `MediaSourceItem` to avoid redundant allocations beyond `pageSize`.
        let sortedNames = shareNames.sorted { lhs, rhs in
            let cmp = lhs.localizedStandardCompare(rhs)
            if cmp == .orderedSame {
                return sortOrder == .ascending ? lhs < rhs : lhs > rhs
            }
            return sortOrder == .ascending ? cmp == .orderedAscending : cmp == .orderedDescending
        }

        guard offset < sortedNames.count else {
            return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: sortedNames.count)
        }

        let endIndex = min(offset + pageSize, sortedNames.count)
        let pageItems = sortedNames[offset..<endIndex].map { name in
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
        let nextCursor = endIndex < sortedNames.count ? String(endIndex) : nil
        return SMBDirectoryPage(items: pageItems, nextCursor: nextCursor, totalCount: sortedNames.count)
    }

    private func loadDirectoryPage(
        in folder: MediaSourceItem,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        cursor: String?,
        pageSize: Int
    ) async throws -> SMBDirectoryPage {
        let shareName: String
        let relativePath: String

        if let explicitShare = folder.smbShare {
            shareName = explicitShare
            relativePath = folder.smbPath ?? ""
        } else {
            let components = folder.path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            guard let shareNameSub = components.first else {
                return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: 0)
            }
            shareName = String(shareNameSub)
            relativePath = components.count > 1 ? String(components[1]) : ""
        }

        let rawPage = try await client.listDirectoryPage(
            share: shareName,
            path: relativePath,
            cursor: cursor,
            pageSize: pageSize,
            sortBy: sortKey,
            order: sortOrder
        )
        try Task.checkCancellation()

        // Only enrich SMB context metadata on the bounded slice returned by the client.
        let normalizedItems = rawPage.items.map { item in
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

        return SMBDirectoryPage(
            items: normalizedItems,
            nextCursor: rawPage.nextCursor,
            totalCount: rawPage.totalCount
        )
    }
}
