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
    private(set) var connectShareCalls: [String] = []
    private(set) var disconnectShareCallCount: Int = 0
    private(set) var downloadAttempts: [DownloadAttempt] = []

    init(
        onDownload: @escaping @Sendable (Int, String, URL, (@Sendable (Int64, Int64) -> Bool)?) async throws -> Void
    ) {
        self.onDownload = onDownload
    }

    func connectShare(name: String) async throws {
        connectShareCalls.append(name)
    }

    func disconnectShare() async throws {
        disconnectShareCallCount += 1
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
}
