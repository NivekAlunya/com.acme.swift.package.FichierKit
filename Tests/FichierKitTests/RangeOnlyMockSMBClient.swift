//
//  RangeOnlyMockSMBClient.swift
//  FichierKitTests
//
//

import Foundation
import FichierKit

/// Range-only `SMBClientProtocol` test double that relies on the protocol's default `downloadFile` implementation.
actor RangeOnlyMockSMBClient: SMBClientProtocol {
    private let files: [String: Data]
    private let reportedSizes: [String: Int64]
    private let failAfterReadCount: Int?
    private let errorToThrow: any Error
    private let onRangeRead: (@Sendable (Int) async throws -> Void)?

    private(set) var recordedRanges: [(offset: Int64, length: Int)] = []
    private(set) var readFileDataCallCount: Int = 0

    init(
        files: [String: Data] = [:],
        reportedSizes: [String: Int64] = [:],
        failAfterReadCount: Int? = nil,
        errorToThrow: any Error = SMBError.timeout,
        onRangeRead: (@Sendable (Int) async throws -> Void)? = nil
    ) {
        self.files = files
        self.reportedSizes = reportedSizes
        self.failAfterReadCount = failAfterReadCount
        self.errorToThrow = errorToThrow
        self.onRangeRead = onRangeRead
    }

    func listShares() async throws -> [String] {
        []
    }

    func listDirectory(share: String, path: String) async throws -> [MediaSourceItem] {
        []
    }

    func readFileData(share: String, path: String, maxBytes: Int64?) async throws -> Data {
        readFileDataCallCount += 1
        throw SMBError.unknown("readFileData should not be invoked by range-streamed default downloadFile.")
    }

    func readMediaRange(share: String, path: String, offset: Int64, length: Int) async throws -> Data {
        recordedRanges.append((offset: offset, length: length))
        let callIndex = recordedRanges.count

        if let failAfterReadCount, callIndex > failAfterReadCount {
            throw errorToThrow
        }

        if let onRangeRead {
            try await onRangeRead(callIndex)
        }

        let key = "\(share)/\(path)"
        guard let data = files[key], offset >= 0, offset < Int64(data.count), length > 0 else {
            return Data()
        }

        let start = Int(offset)
        let end = min(data.count, start + length)
        return data.subdata(in: start..<end)
    }

    func fileSize(share: String, path: String) async throws -> Int64 {
        let key = "\(share)/\(path)"
        if let explicitSize = reportedSizes[key] {
            return explicitSize
        }
        return Int64(files[key]?.count ?? 0)
    }

    func disconnect() async {}
}
