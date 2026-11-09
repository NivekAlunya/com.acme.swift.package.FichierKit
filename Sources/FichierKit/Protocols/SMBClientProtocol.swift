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
}

public extension SMBClientProtocol {
    /// Streams a remote file directly to a local file URL without a progress callback.
    func downloadFile(share: String, path: String, to localURL: URL) async throws {
        try await downloadFile(share: share, path: path, to: localURL, progress: nil)
    }

    /// Default buffered fallback when an `SMBClientProtocol` implementation does not override direct streaming download.
    func downloadFile(
        share: String,
        path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws {
        try Task.checkCancellation()
        let total = try await fileSize(share: share, path: path)
        let data = try await readFileData(share: share, path: path, maxBytes: nil)
        try Task.checkCancellation()
        if let progress, !progress(Int64(data.count), max(total, Int64(data.count))) {
            throw CancellationError()
        }
        try data.write(to: localURL, options: .atomic)
    }
}
