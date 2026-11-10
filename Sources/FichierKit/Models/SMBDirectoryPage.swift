//
//  SMBDirectoryPage.swift
//  FichierKit
//
//

import Foundation

/// A bounded page of directory items returned by paginated SMB enumeration.
public struct SMBDirectoryPage: Sendable, Equatable {
    /// Ordered slice of folder and media items included in this page.
    public let items: [MediaSourceItem]

    /// Opaque continuation cursor used to fetch the next page, or `nil` when no further pages remain.
    public let nextCursor: String?

    /// Total item count in the directory when known by the backend or index, or `nil` when streaming incrementally.
    public let totalCount: Int?

    /// Indicates whether additional pages may exist after this page.
    public var hasMore: Bool {
        nextCursor != nil
    }

    public init(
        items: [MediaSourceItem],
        nextCursor: String? = nil,
        totalCount: Int? = nil
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.totalCount = totalCount
    }
}
