//
//  MediaSource.swift
//  FichierKit
//

import Foundation

/// Abstraction defining media backends (Photos, SMB Shares).
///
/// Both sources return items that are a folder, an image, or a video,
/// declaring supported sort keys and their preferred visual layout.
public protocol MediaSource: Sendable {
    /// Unique identifier distinguishing this media source instance.
    var id: String { get }

    /// Localized display name of the source.
    var displayName: String { get }

    /// Preferred layout format for displaying items (grid for Photos, list for Shares).
    var preferredLayout: MediaSourceLayout { get }

    /// The sort keys supported by this source.
    var supportedSortKeys: Set<MediaSortKey> { get }

    /// Fetches items contained in a given folder (or root if `nil`), with pagination and sorting.
    ///
    /// - Parameters:
    ///   - folder: The parent folder, or `nil` for the root container.
    ///   - sortKey: Active sort key (must be one of `supportedSortKeys`).
    ///   - sortOrder: Sort direction.
    ///   - page: Zero-based page offset.
    ///   - pageSize: Number of items requested per page.
    /// - Returns: A paginated slice of `MediaSourceItem` elements.
    func fetchItems(
        in folder: MediaSourceItem?,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        page: Int,
        pageSize: Int
    ) async throws -> [MediaSourceItem]
}
