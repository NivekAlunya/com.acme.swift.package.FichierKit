//
//  SMB2SessionProtocol.swift
//  FichierKit
//
//

import Foundation

/// Internal abstraction over `AMSMB2.SMB2Manager` operations for testability without a live SMB server.
protocol SMB2SessionProtocol: Sendable {
    func connectShare(name: String) async throws
    func disconnectShare() async throws
    func listShareNames(enumerateHidden: Bool) async throws -> [String]
    func directoryEntries(atPath path: String) async throws -> [SMB2DirectoryEntry]
    func readContents(
        atPath path: String,
        range: Range<Int64>?,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws -> Data
    func fileSize(atPath path: String) async throws -> Int64
    func downloadItem(
        atPath path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws
}
