//
//  MockSMB2Session.swift
//  FichierKitTests
//
//

import Foundation
@testable import FichierKit

/// Actor-isolated mock `SMB2SessionProtocol` allowing atomic download, retry, and cancellation tests
/// against `AMSMB2Client` without connecting to a live SMB server.
actor MockSMB2Session: SMB2SessionProtocol {
    struct DownloadAttempt: Sendable, Equatable {
        let path: String
        let destinationURL: URL
    }

    private let onDownload: @Sendable (Int, String, URL, (@Sendable (Int64, Int64) -> Bool)?) async throws -> Void
    var onCreateDirectory: (@Sendable (String) async throws -> Void)?
    var onRemoveItem: (@Sendable (String) async throws -> Void)?
    var onMoveItem: (@Sendable (String, String) async throws -> Void)?

    private(set) var connectShareCalls: [String] = []
    private(set) var disconnectShareCallCount: Int = 0
    private(set) var lastDisconnectGraceful: Bool?
    private(set) var disconnectShareCalls: [Bool] = []
    private(set) var downloadAttempts: [DownloadAttempt] = []
    private(set) var createdDirectories: [String] = []
    private(set) var removedItems: [String] = []
    private(set) var movedItems: [(from: String, to: String)] = []

    init(
        onDownload: @escaping @Sendable (Int, String, URL, (@Sendable (Int64, Int64) -> Bool)?) async throws -> Void = { _, _, _, _ in }
    ) {
        self.onDownload = onDownload
    }

    func connectShare(name: String) async throws {
        connectShareCalls.append(name)
    }

    func disconnectShare(gracefully: Bool) async throws {
        disconnectShareCallCount += 1
        lastDisconnectGraceful = gracefully
        disconnectShareCalls.append(gracefully)
    }

    func listShareNames(enumerateHidden: Bool) async throws -> [String] {
        []
    }

    func directoryEntries(atPath path: String) async throws -> [SMB2DirectoryEntry] {
        []
    }

    func readContents(
        atPath path: String,
        range: Range<Int64>?,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws -> Data {
        Data()
    }

    func fileSize(atPath path: String) async throws -> Int64 {
        0
    }

    func downloadItem(
        atPath path: String,
        to localURL: URL,
        progress: (@Sendable (Int64, Int64) -> Bool)?
    ) async throws {
        downloadAttempts.append(DownloadAttempt(path: path, destinationURL: localURL))
        let attemptNumber = downloadAttempts.count
        try await onDownload(attemptNumber, path, localURL, progress)
    }

    func createDirectory(atPath path: String) async throws {
        createdDirectories.append(path)
        if let onCreateDirectory {
            try await onCreateDirectory(path)
        }
    }

    func removeItem(atPath path: String) async throws {
        removedItems.append(path)
        if let onRemoveItem {
            try await onRemoveItem(path)
        }
    }

    func moveItem(atPath path: String, toPath: String) async throws {
        movedItems.append((from: path, to: toPath))
        if let onMoveItem {
            try await onMoveItem(path, toPath)
        }
    }
}
