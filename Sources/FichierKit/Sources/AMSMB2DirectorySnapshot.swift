//
//  AMSMB2DirectorySnapshot.swift
//  FichierKit
//
//

import Foundation

/// Compact sorted directory index cached across sequential page requests in `AMSMB2Client`.
struct AMSMB2DirectorySnapshot: Sendable {
    let share: String
    let normalizedPath: String
    let sortKey: MediaSortKey
    let sortOrder: MediaSortOrder
    let items: [MediaSourceItem]
}
