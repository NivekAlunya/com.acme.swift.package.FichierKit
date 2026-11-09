//
//  SMBClientProtocol.swift
//  FichierKit
//
//

import Foundation

/// Abstraction for SMB network file system operations.
public protocol SMBClientProtocol: Sendable {
    /// Discovers and returns available share names on the connected server.
    func listShares() async throws -> [String]

    /// Lists child items within a specified share and directory path.
    func listDirectory(share: String, path: String) async throws -> [MediaSourceItem]

    /// Lists a bounded page of child items within a specified share and directory path.
    ///
    /// Backends supporting incremental or cursor-based enumeration should implement this directly
    /// to avoid full-directory materialization before paging. When a backend cannot enumerate
    /// incrementally or sort server-side (such as `AMSMB2` / SMB2 `QUERY_DIRECTORY`), sorting across
    /// the directory requires inspecting all entries once before paging; implementations should still
    /// drop raw entries early and release transient index state on completion or disconnect.
    func listDirectoryPage(
        share: String,
        path: String,
        cursor: String?,
        pageSize: Int,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder
    ) async throws -> SMBDirectoryPage

    /// Reads file contents (or a bounded byte prefix when `maxBytes` is specified).
    func readFileData(share: String, path: String, maxBytes: Int64?) async throws -> Data

    /// Reads an exact byte range from a remote file for HTTP range streaming.
    func readMediaRange(share: String, path: String, offset: Int64, length: Int) async throws -> Data

    /// Queries the byte length of a file on the remote share.
    func fileSize(share: String, path: String) async throws -> Int64

    /// Streams a remote file directly to a local file URL with optional progress reporting and cancellation.
    func downloadFile(
        share: String,
        path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws

    /// Disconnects the active SMB session cleanly. Implementations must be idempotent and safe when no session is active.
    func disconnect() async
}

public extension SMBClientProtocol {
    /// Default bounded-page fallback using `listDirectory(share:path:)` with folder-first deterministic sorting.
    func listDirectoryPage(
        share: String,
        path: String,
        cursor: String?,
        pageSize: Int,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder
    ) async throws -> SMBDirectoryPage {
        try Task.checkCancellation()
        guard pageSize > 0 else {
            return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: nil)
        }

        let offset: Int
        if let cursor {
            guard let parsedOffset = Int(cursor), parsedOffset >= 0 else {
                return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: nil)
            }
            offset = parsedOffset
        } else {
            offset = 0
        }

        let allItems = try await listDirectory(share: share, path: path)
        try Task.checkCancellation()

        let sorted = MediaSourceItemSortComparator.sortFoldersFirst(
            allItems,
            sortBy: sortKey,
            order: sortOrder
        )
        guard offset < sorted.count else {
            return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: sorted.count)
        }

        let endIndex = min(offset + pageSize, sorted.count)
        let slice = Array(sorted[offset..<endIndex])
        let nextCursor = endIndex < sorted.count ? String(endIndex) : nil
        return SMBDirectoryPage(items: slice, nextCursor: nextCursor, totalCount: sorted.count)
    }

    /// Streams a remote file directly to a local file URL without a progress callback.
    func downloadFile(share: String, path: String, to localURL: URL) async throws {
        try await downloadFile(share: share, path: path, to: localURL, progress: nil)
    }

    /// Default 1 MiB chunked range-streaming fallback when an `SMBClientProtocol` implementation does not override direct streaming download.
    func downloadFile(
        share: String,
        path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws {
        try Task.checkCancellation()
        let total = try await fileSize(share: share, path: path)
        try Task.checkCancellation()

        let chunkSize = 1_048_576
        let directoryURL = localURL.deletingLastPathComponent()
        let tempURL = directoryURL.appendingPathComponent("\(localURL.lastPathComponent).\(UUID().uuidString).part")

        try Data().write(to: tempURL, options: .withoutOverwriting)
        var shouldCleanupTempFile = true
        var fileHandle: FileHandle?

        defer {
            if let openHandle = fileHandle {
                try? openHandle.close()
                fileHandle = nil
            }
            if shouldCleanupTempFile {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        let openedHandle = try FileHandle(forWritingTo: tempURL)
        fileHandle = openedHandle

        var bytesWritten: Int64 = 0

        if total > 0 {
            while bytesWritten < total {
                try Task.checkCancellation()
                let remaining = total - bytesWritten
                let requestLength = Int(min(Int64(chunkSize), remaining))
                let chunk = try await readMediaRange(
                    share: share,
                    path: path,
                    offset: bytesWritten,
                    length: requestLength
                )
                try Task.checkCancellation()
                guard !chunk.isEmpty else {
                    throw SMBError.unknown("Unexpected end of file before completing download.")
                }

                let payload: Data
                if Int64(chunk.count) > remaining {
                    payload = chunk.prefix(Int(remaining))
                } else {
                    payload = chunk
                }

                try openedHandle.write(contentsOf: payload)
                bytesWritten += Int64(payload.count)

                if let progress, !progress(bytesWritten, total) {
                    throw CancellationError()
                }
            }
        } else {
            while true {
                try Task.checkCancellation()
                let chunk = try await readMediaRange(
                    share: share,
                    path: path,
                    offset: bytesWritten,
                    length: chunkSize
                )
                try Task.checkCancellation()
                if chunk.isEmpty {
                    break
                }

                try openedHandle.write(contentsOf: chunk)
                bytesWritten += Int64(chunk.count)

                if let progress, !progress(bytesWritten, bytesWritten) {
                    throw CancellationError()
                }
            }
        }

        try Task.checkCancellation()
        fileHandle = nil
        try openedHandle.close()

        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: localURL.path) {
            _ = try FileManager.default.replaceItemAt(
                localURL,
                withItemAt: tempURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: tempURL, to: localURL)
        }
        shouldCleanupTempFile = false
    }
}
