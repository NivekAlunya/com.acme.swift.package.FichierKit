//
//  SavedFolderLocation.swift
//  FichierKit
//

import Foundation

/// Persisted configuration record for an external sandboxed folder (Local or iCloud Drive).
///
/// Stores security-scoped bookmark data that allows persistent sandbox escape across application
/// launches without prompting the user repeatedly via file picker dialogs.
nonisolated public struct SavedFolderLocation: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier for this saved folder location.
    public let id: String

    /// User-visible directory name (e.g. "Downloads" or "Vacation 2026").
    public let name: String

    /// Binary security-scoped bookmark data created via `URL.bookmarkData(...)`.
    public let bookmarkData: Data

    /// Indicates whether the folder is hosted inside ubiquitous iCloud Drive storage.
    public let isICloud: Bool

    /// Timestamp when this folder was picked and added by the user.
    public let dateAdded: Date
    
    /// Memberwise initializer with sensible defaults.
    ///
    /// - Parameters:
    ///   - id: Unique UUID string identifier.
    ///   - name: Directory name.
    ///   - bookmarkData: Encoded security-scoped bookmark.
    ///   - isICloud: Whether folder is in iCloud Drive.
    ///   - dateAdded: Addition timestamp.
    nonisolated public init(
        id: String = UUID().uuidString,
        name: String,
        bookmarkData: Data,
        isICloud: Bool,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
        self.isICloud = isICloud
        self.dateAdded = dateAdded
    }
}
