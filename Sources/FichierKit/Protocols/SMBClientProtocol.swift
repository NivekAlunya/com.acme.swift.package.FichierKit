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
}
