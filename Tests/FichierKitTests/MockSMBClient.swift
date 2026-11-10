//
//  MockSMBClient.swift
//  FichierKitTests
//
//

import Foundation
import FichierKit

/// Mock SMB client implementation for testing `SharesMediaSource` and SMB streaming/image helpers.
final class MockSMBClient: SMBClientProtocol, Sendable {
    let mockShares: [String]
    let mockItems: [MediaSourceItem]
    let mockFileData: [String: Data]

    init(
        mockShares: [String] = ["Media", "Photos", "Backups"],
        mockItems: [MediaSourceItem] = [],
        mockFileData: [String: Data] = [:]
    ) {
        self.mockShares = mockShares
        self.mockItems = mockItems
        self.mockFileData = mockFileData
    }

    func listShares() async throws -> [String] {
        mockShares
    }

    func listDirectory(share: String, path: String) async throws -> [MediaSourceItem] {
        mockItems
    }

    func readFileData(share: String, path: String, maxBytes: Int64?) async throws -> Data {
        let key = "\(share)/\(path)"
        guard let data = mockFileData[key] else {
            return Data()
        }
        if let maxBytes, maxBytes > 0, data.count > Int(maxBytes) {
            return data.prefix(Int(maxBytes))
        }
        return data
    }

    func readMediaRange(share: String, path: String, offset: Int64, length: Int) async throws -> Data {
        let key = "\(share)/\(path)"
        guard let data = mockFileData[key], offset >= 0, offset < Int64(data.count), length > 0 else {
            return Data()
        }
        let start = Int(offset)
        let end = min(data.count, start + length)
        return data.subdata(in: start..<end)
    }

    func fileSize(share: String, path: String) async throws -> Int64 {
        let key = "\(share)/\(path)"
        return Int64(mockFileData[key]?.count ?? 0)
    }

    func downloadFile(
        share: String,
        path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws {
        try Task.checkCancellation()
        let key = "\(share)/\(path)"
        guard let data = mockFileData[key] else {
            throw SMBError.shareNotFound(key)
        }
        let total = Int64(data.count)
        if let progress, !progress(total, total) {
            throw CancellationError()
        }
        try data.write(to: localURL, options: .atomic)
    }

    func disconnect() async {}
}
