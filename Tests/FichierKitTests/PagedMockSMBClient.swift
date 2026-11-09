//
//  PagedMockSMBClient.swift
//  FichierKitTests
//
//

import Foundation
import FichierKit

/// Actor-backed `SMBClientProtocol` test double implementing native cursor-based `listDirectoryPage`
/// and tracking `disconnect()` calls without delegating to `listDirectory(share:path:)`.
actor PagedMockSMBClient: SMBClientProtocol {
    struct PageRequest: Equatable, Sendable {
        let share: String
        let path: String
        let cursor: String?
        let pageSize: Int
        let sortKey: MediaSortKey
        let sortOrder: MediaSortOrder
    }

    static let initialCursorKey = "__initial__"

    private let mockShares: [String]
    private let pagesByCursor: [String: SMBDirectoryPage]

    private(set) var disconnectCallCount: Int = 0
    private(set) var listDirectoryCallCount: Int = 0
    private(set) var requestedPages: [PageRequest] = []

    init(
        mockShares: [String] = [],
        pagesByCursor: [String: SMBDirectoryPage] = [:]
    ) {
        self.mockShares = mockShares
        self.pagesByCursor = pagesByCursor
    }

    func listShares() async throws -> [String] {
        try Task.checkCancellation()
        return mockShares
    }

    func listDirectory(share: String, path: String) async throws -> [MediaSourceItem] {
        listDirectoryCallCount += 1
        throw SMBError.unknown("listDirectory should not be called when listDirectoryPage is supported.")
    }

    func listDirectoryPage(
        share: String,
        path: String,
        cursor: String?,
        pageSize: Int,
        sortBy sortKey: MediaSortKey,
        order sortOrder: MediaSortOrder
    ) async throws -> SMBDirectoryPage {
        try Task.checkCancellation()
        requestedPages.append(
            PageRequest(
                share: share,
                path: path,
                cursor: cursor,
                pageSize: pageSize,
                sortKey: sortKey,
                sortOrder: sortOrder
            )
        )
        guard pageSize > 0 else {
            return SMBDirectoryPage(items: [], nextCursor: nil, totalCount: nil)
        }
        let lookupKey = cursor ?? Self.initialCursorKey
        return pagesByCursor[lookupKey] ?? SMBDirectoryPage(items: [], nextCursor: nil, totalCount: nil)
    }

    func readFileData(share: String, path: String, maxBytes: Int64?) async throws -> Data {
        Data()
    }

    func readMediaRange(share: String, path: String, offset: Int64, length: Int) async throws -> Data {
        Data()
    }

    func fileSize(share: String, path: String) async throws -> Int64 {
        0
    }

    func disconnect() async {
        disconnectCallCount += 1
    }
}
