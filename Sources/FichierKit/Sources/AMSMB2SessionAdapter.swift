//
//  AMSMB2SessionAdapter.swift
//  FichierKit
//
//

import Foundation
import AMSMB2

/// Bridges `AMSMB2.SMB2Manager` to `SMB2SessionProtocol`.
///
/// Marked `@unchecked Sendable` strictly because `SMB2Manager` comes from `AMSMB2`/`libsmb2`
/// without `Sendable` annotation; all calls are serialized inside `actor AMSMB2Client` via `operationLimiter`.
final class AMSMB2SessionAdapter: SMB2SessionProtocol, @unchecked Sendable {
    private let manager: SMB2Manager

    init(manager: SMB2Manager) {
        self.manager = manager
    }

    func connectShare(name: String) async throws {
        try await manager.connectShare(name: name)
    }

    func disconnectShare() async throws {
        try await manager.disconnectShare()
    }

    func listShareNames(enumerateHidden: Bool) async throws -> [String] {
        let shares = try await manager.listShares(enumerateHidden: enumerateHidden)
        return shares.map(\.name)
    }

    func directoryEntries(atPath path: String) async throws -> [SMB2DirectoryEntry] {
        let entries = try await manager.contentsOfDirectory(atPath: path)
        return entries.map { entry in
            let resourceType = entry[.fileResourceTypeKey] as? URLFileResourceType
            return SMB2DirectoryEntry(
                name: entry[.nameKey] as? String,
                path: entry[.pathKey] as? String,
                isDirectory: resourceType == .directory,
                isRegularFile: resourceType == .regular,
                fileSize: Self.extractFileSize(from: entry),
                modifiedDate: entry[.contentModificationDateKey] as? Date
            )
        }
    }

    func readContents(
        atPath path: String,
        range: Range<Int64>?,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws -> Data {
        if let range {
            return try await manager.contents(atPath: path, range: range) { bytes, total in
                progress?(bytes, total) ?? true
            }
        } else {
            return try await manager.contents(atPath: path, range: Range<UInt64>?.none) { bytes, total in
                progress?(bytes, total) ?? true
            }
        }
    }

    func fileSize(atPath path: String) async throws -> Int64 {
        let attrs = try await manager.attributesOfItem(atPath: path)
        return Self.extractFileSize(from: attrs)
    }

    func downloadItem(
        atPath path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws {
        try await manager.downloadItem(atPath: path, to: localURL) { bytes, total in
            progress?(bytes, total) ?? true
        }
    }

    private static func extractFileSize(from dict: [URLResourceKey: Any]) -> Int64 {
        if let number = dict[.fileSizeKey] as? NSNumber {
            return number.int64Value
        }
        if let val = dict[.fileSizeKey] as? Int64 {
            return val
        }
        if let val = dict[.fileSizeKey] as? UInt64 {
            return Int64(min(val, UInt64(Int64.max)))
        }
        if let val = dict[.fileSizeKey] as? Int {
            return Int64(val)
        }
        return 0
    }
}
