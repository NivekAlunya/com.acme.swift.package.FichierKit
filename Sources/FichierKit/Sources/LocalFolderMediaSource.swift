//
//  LocalFolderMediaSource.swift
//  FichierKit
//

import Foundation

/// Media source backed by a local or sandboxed filesystem directory.
///
/// Implements `MediaSource` to enumerate, paginate, and sort files and subfolders.
public final class LocalFolderMediaSource: MediaSource, Sendable {

    /// Unique identifier distinguishing this media source instance.
    public let id: String

    /// User-facing display title for this storage location.
    public let displayName: String

    /// Root directory URL accessible by this media source.
    public let rootURL: URL

    /// Preferred visual layout (defaults to `.grid`).
    public let preferredLayout: MediaSourceLayout

    /// Set of sort keys supported by this local source.
    public let supportedSortKeys: Set<MediaSortKey> = [.name, .date, .size, .type, .kind, .resolution, .duration]

    var fileManager: FileManager { .default }

    private static let enumerationKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .nameKey
    ]

    /// Initializes a local folder media source for the given directory URL.
    ///
    /// - Parameters:
    ///   - rootURL: Base file URL of the folder.
    ///   - id: Optional unique identifier; defaults to standardized root URL path.
    ///   - displayName: Optional display name; defaults to root URL last path component.
    ///   - preferredLayout: Visual layout preference; defaults to `.grid`.
    public init(
        rootURL: URL,
        id: String? = nil,
        displayName: String? = nil,
        preferredLayout: MediaSourceLayout = .grid
    ) {
        let standardized = rootURL.standardizedFileURL
        self.rootURL = standardized
        self.id = id ?? standardized.path
        let fallbackName = standardized.lastPathComponent.isEmpty ? "Folder" : standardized.lastPathComponent
        self.displayName = displayName ?? fallbackName
        self.preferredLayout = preferredLayout
    }

    // MARK: - MediaSource Conformance

    /// Fetches child items in the given folder (or root directory if `nil`) with sorting and pagination.
    ///
    /// - Parameters:
    ///   - folder: The parent folder `MediaSourceItem`, or `nil` for the root container.
    ///   - sortKey: Active sort key.
    ///   - sortOrder: Sort direction.
    ///   - page: Zero-based page offset.
    ///   - pageSize: Number of items requested per page.
    /// - Returns: A paginated slice of sorted `MediaSourceItem` elements.
    public func fetchItems(
        in folder: MediaSourceItem?,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder,
        page: Int,
        pageSize: Int
    ) async throws -> [MediaSourceItem] {
        try Task.checkCancellation()
        guard page >= 0, pageSize > 0 else { return [] }

        let targetURL = resolveTargetURL(for: folder)
        let contents = try fileManager.contentsOfDirectory(
            at: targetURL,
            includingPropertiesForKeys: Self.enumerationKeys,
            options: [.skipsHiddenFiles]
        )

        var items: [MediaSourceItem] = []
        items.reserveCapacity(contents.count)

        for url in contents {
            try Task.checkCancellation()
            if let item = createMediaSourceItem(at: url, in: folder) {
                items.append(item)
            }
        }

        let sorted = MediaSourceItemSortComparator.sortFoldersFirst(items, sortBy: sortKey, order: sortOrder)
        let start = page * pageSize
        guard start < sorted.count else { return [] }
        let end = min(start + pageSize, sorted.count)
        return Array(sorted[start..<end])
    }

    // MARK: - Private Helpers

    private func resolveTargetURL(for folder: MediaSourceItem?) -> URL {
        guard let folder else { return rootURL }
        if let local = folder.localURL {
            return local.standardizedFileURL
        }
        return rootURL.appendingPathComponent(folder.path, isDirectory: true).standardizedFileURL
    }

    private func createMediaSourceItem(at url: URL, in folder: MediaSourceItem?) -> MediaSourceItem? {
        let resourceValues = try? url.resourceValues(forKeys: Set(Self.enumerationKeys))
        let isDir = resourceValues?.isDirectory ?? false
        let name = resourceValues?.name ?? url.lastPathComponent
        let size = Int64(resourceValues?.fileSize ?? 0)
        let date = resourceValues?.contentModificationDate
        let ext = url.pathExtension.lowercased()

        let relativePath: String
        if let folder {
            relativePath = folder.path.isEmpty ? name : "\(folder.path)/\(name)"
        } else {
            relativePath = name
        }

        if isDir {
            return MediaSourceItem(
                id: "\(id)::\(relativePath)",
                name: name,
                path: relativePath,
                type: .folder,
                size: 0,
                modifiedDate: date,
                localURL: url,
                sourceID: id
            )
        }

        guard let itemType = MediaItemType.from(extension: ext) else { return nil }

        return MediaSourceItem(
            id: "\(id)::\(relativePath)",
            name: name,
            path: relativePath,
            type: itemType,
            size: size,
            modifiedDate: date,
            localURL: url,
            sourceID: id
        )
    }
}
