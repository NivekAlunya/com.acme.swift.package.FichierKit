//
//  MockSMBClient.swift
//  FichierKitTests
//
//

import Foundation
import Synchronization
import FichierKit

/// Mock SMB client implementation for testing `SharesMediaSource` and SMB streaming/image helpers.
final class MockSMBClient: SMBClientProtocol, Sendable {
    struct State: Sendable {
        var shares: [String]
        var items: [MediaSourceItem]
        var fileData: [String: Data]
        var createdDirectories: [(share: String, path: String)] = []
        var removedItems: [(share: String, path: String)] = []
        var movedItems: [(share: String, from: String, to: String)] = []
    }

    private let state: Mutex<State>

    var mockShares: [String] { state.withLock { $0.shares } }
    var mockItems: [MediaSourceItem] { state.withLock { $0.items } }
    var mockFileData: [String: Data] { state.withLock { $0.fileData } }
    var createdDirectories: [(share: String, path: String)] { state.withLock { $0.createdDirectories } }
    var removedItems: [(share: String, path: String)] { state.withLock { $0.removedItems } }
    var movedItems: [(share: String, from: String, to: String)] { state.withLock { $0.movedItems } }

    init(
        mockShares: [String] = ["Media", "Photos", "Backups"],
        mockItems: [MediaSourceItem] = [],
        mockFileData: [String: Data] = [:]
    ) {
        self.state = Mutex(
            State(
                shares: mockShares,
                items: mockItems,
                fileData: mockFileData
            )
        )
    }

    func listShares() async throws -> [String] {
        state.withLock { $0.shares }
    }

    func listDirectory(share: String, path: String) async throws -> [MediaSourceItem] {
        state.withLock { $0.items }
    }

    func readFileData(share: String, path: String, maxBytes: Int64?) async throws -> Data {
        let key = "\(share)/\(path)"
        guard let data = state.withLock({ $0.fileData[key] }) else {
            return Data()
        }
        if let maxBytes, maxBytes > 0, data.count > Int(maxBytes) {
            return data.prefix(Int(maxBytes))
        }
        return data
    }

    func readMediaRange(share: String, path: String, offset: Int64, length: Int) async throws -> Data {
        let key = "\(share)/\(path)"
        guard let data = state.withLock({ $0.fileData[key] }), offset >= 0, offset < Int64(data.count), length > 0 else {
            return Data()
        }
        let start = Int(offset)
        let end = min(data.count, start + length)
        return data.subdata(in: start..<end)
    }

    func fileSize(share: String, path: String) async throws -> Int64 {
        let key = "\(share)/\(path)"
        return Int64(state.withLock { $0.fileData[key]?.count ?? 0 })
    }

    func downloadFile(
        share: String,
        path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws {
        try Task.checkCancellation()
        let key = "\(share)/\(path)"
        guard let data = state.withLock({ $0.fileData[key] }) else {
            throw SMBError.shareNotFound(key)
        }
        let total = Int64(data.count)
        if let progress, !progress(total, total) {
            throw CancellationError()
        }
        try data.write(to: localURL, options: .atomic)
    }

    func createDirectory(share: String, path: String) async throws {
        state.withLock {
            $0.createdDirectories.append((share: share, path: path))
            let folderItem = MediaSourceItem(
                id: "\(share)::/\(path)",
                name: (path as NSString).lastPathComponent,
                path: "\(share)/\(path)",
                type: .folder,
                size: 0,
                modifiedDate: Date(),
                smbShare: share,
                smbPath: path
            )
            $0.items.append(folderItem)
        }
    }

    func removeItem(share: String, path: String) async throws {
        state.withLock {
            $0.removedItems.append((share: share, path: path))
            $0.items.removeAll { $0.smbPath == path || $0.path == "\(share)/\(path)" }
            $0.fileData.removeValue(forKey: "\(share)/\(path)")
        }
    }

    func moveItem(share: String, fromPath: String, toPath: String) async throws {
        state.withLock {
            $0.movedItems.append((share: share, from: fromPath, to: toPath))
            if let index = $0.items.firstIndex(where: { $0.smbPath == fromPath || $0.path == "\(share)/\(fromPath)" }) {
                let old = $0.items[index]
                let updated = MediaSourceItem(
                    id: "\(share)::/\(toPath)",
                    name: (toPath as NSString).lastPathComponent,
                    path: "\(share)/\(toPath)",
                    type: old.type,
                    size: old.size,
                    modifiedDate: old.modifiedDate,
                    smbShare: share,
                    smbPath: toPath
                )
                $0.items[index] = updated
            }
            if let data = $0.fileData.removeValue(forKey: "\(share)/\(fromPath)") {
                $0.fileData["\(share)/\(toPath)"] = data
            }
        }
    }

    func disconnect() async {}
}
