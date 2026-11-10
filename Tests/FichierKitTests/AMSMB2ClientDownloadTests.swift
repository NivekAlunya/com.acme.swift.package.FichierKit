//
//  AMSMB2ClientDownloadTests.swift
//  FichierKitTests
//
//

import Foundation
import Testing
@testable import FichierKit

@Suite("AMSMB2Client Atomic Download Tests")
struct AMSMB2ClientDownloadTests {
    private static let testServer = SavedSMBConnection(
        host: "192.168.1.55",
        username: "tester",
        lastConnected: Date(timeIntervalSince1970: 1_700_000_000)
    )

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichierkit_amsmb2_dl_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Successful download stages into temporary .part file and replaces existing destination only on completion")
    func testSuccessfulDownloadReplacesDestinationAtomicallyAfterCompletion() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let destinationURL = dir.appendingPathComponent("movie.mp4")
        let originalData = Data("Original Existing Video".utf8)
        let newData = Data("New Downloaded Video Payload".utf8)
        try originalData.write(to: destinationURL)

        let (seenInFlightOriginalStream, seenInFlightContinuation) = AsyncStream.makeStream(of: Bool.self)
        let session = MockSMB2Session { attempt, path, tempURL, progress in
            #expect(attempt == 1)
            #expect(path == "Movies/movie.mp4")
            #expect(tempURL != destinationURL)
            #expect(tempURL.pathExtension == "part")

            // While download is still in flight, destinationURL must keep its original content
            let currentDest = try Data(contentsOf: destinationURL)
            seenInFlightContinuation.yield(currentDest == originalData)
            seenInFlightContinuation.finish()

            try newData.write(to: tempURL)
            _ = progress?(Int64(newData.count / 2), Int64(newData.count))
            _ = progress?(Int64(newData.count), Int64(newData.count))
        }

        let client = AMSMB2Client(server: Self.testServer, password: "secret") { _, _ in session }
        let (progressStream, progressContinuation) = AsyncStream.makeStream(of: (Int64, Int64).self)

        try await client.downloadFile(share: "Media", path: "/Movies/movie.mp4", to: destinationURL) { bytes, total in
            progressContinuation.yield((bytes, total))
            return true
        }
        progressContinuation.finish()

        var inFlightPreserved = false
        for await preserved in seenInFlightOriginalStream {
            inFlightPreserved = preserved
        }
        #expect(inFlightPreserved)

        var recordedProgress: [(Int64, Int64)] = []
        for await item in progressStream {
            recordedProgress.append(item)
        }
        #expect(recordedProgress.count == 2)
        #expect(recordedProgress.last?.0 == Int64(newData.count))
        #expect(recordedProgress.last?.1 == Int64(newData.count))

        #expect(try Data(contentsOf: destinationURL) == newData)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["movie.mp4"])
    }

    @Test("Failed first attempt followed by retry uses distinct temp URLs, preserves destination during failure, and cleans .part files")
    func testRetryUsesDistinctTempPathsAndPreservesDestinationUntilSuccess() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let destinationURL = dir.appendingPathComponent("archive.pdf")
        let originalData = Data("Existing Valid PDF".utf8)
        let retryData = Data("Updated Complete PDF".utf8)
        try originalData.write(to: destinationURL)

        let session = MockSMB2Session { attempt, _, tempURL, progress in
            #expect(try Data(contentsOf: destinationURL) == originalData)
            if attempt == 1 {
                try Data("partial corrupt chunk".utf8).write(to: tempURL)
                throw POSIXError(.ECONNRESET)
            }
            try retryData.write(to: tempURL)
            _ = progress?(Int64(retryData.count), Int64(retryData.count))
        }

        let client = AMSMB2Client(server: Self.testServer, password: "secret") { _, _ in session }
        try await client.downloadFile(share: "Docs", path: "archive.pdf", to: destinationURL)

        let attempts = await session.downloadAttempts
        #expect(attempts.count == 2)
        #expect(attempts[0].destinationURL != attempts[1].destinationURL)
        #expect(attempts[0].destinationURL.pathExtension == "part")
        #expect(attempts[1].destinationURL.pathExtension == "part")
        #expect(attempts[0].destinationURL != destinationURL)
        #expect(attempts[1].destinationURL != destinationURL)

        #expect(try Data(contentsOf: destinationURL) == retryData)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["archive.pdf"])
    }

    @Test("Final retry failure preserves existing destination intact and removes all temporary .part files")
    func testFinalFailurePreservesExistingDestinationAndCleansPartFiles() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let destinationURL = dir.appendingPathComponent("important.bin")
        let originalData = Data("Keep Existing Binary Data".utf8)
        try originalData.write(to: destinationURL)

        let session = MockSMB2Session { attempt, _, tempURL, _ in
            try Data("partial attempt \(attempt)".utf8).write(to: tempURL)
            throw POSIXError(.ETIMEDOUT)
        }

        let client = AMSMB2Client(server: Self.testServer, password: "secret") { _, _ in session }

        await #expect(throws: SMBError.timeout) {
            try await client.downloadFile(share: "Media", path: "important.bin", to: destinationURL)
        }

        let attempts = await session.downloadAttempts
        #expect(attempts.count == 2)
        #expect(attempts[0].destinationURL != attempts[1].destinationURL)
        #expect(try Data(contentsOf: destinationURL) == originalData)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["important.bin"])
    }

    @Test("Task cancellation preserves existing destination intact and removes temporary .part files")
    func testTaskCancellationPreservesExistingDestination() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let destinationURL = dir.appendingPathComponent("cancel_target.mp4")
        let originalData = Data("Original Intact Media".utf8)
        try originalData.write(to: destinationURL)

        let (startedStream, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let session = MockSMB2Session { _, _, tempURL, _ in
            try Data("partial in flight bytes".utf8).write(to: tempURL)
            startedContinuation.yield()
            try await Task.sleep(for: .seconds(5))
        }

        let client = AMSMB2Client(server: Self.testServer, password: "secret") { _, _ in session }
        let downloadTask = Task {
            try await client.downloadFile(share: "Media", path: "cancel_target.mp4", to: destinationURL)
        }

        for await _ in startedStream {
            break
        }
        downloadTask.cancel()

        await #expect(throws: CancellationError.self) {
            try await downloadTask.value
        }

        #expect(await session.downloadAttempts.count == 1)
        #expect(try Data(contentsOf: destinationURL) == originalData)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["cancel_target.mp4"])
    }

    @Test("Progress cancellation aborts immediately without retry, preserves existing destination, and cleans .part files")
    func testProgressCancellationPreservesDestinationWithoutRetrying() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let destinationURL = dir.appendingPathComponent("progress_cancel.jpg")
        let originalData = Data("Previous Cached Image".utf8)
        try originalData.write(to: destinationURL)

        let session = MockSMB2Session { _, _, tempURL, progress in
            try Data("partial download".utf8).write(to: tempURL)
            let shouldContinue = progress?(16, 1024) ?? true
            if !shouldContinue {
                throw POSIXError(.ECANCELED)
            }
        }

        let client = AMSMB2Client(server: Self.testServer, password: "secret") { _, _ in session }

        await #expect(throws: CancellationError.self) {
            try await client.downloadFile(share: "Photos", path: "progress_cancel.jpg", to: destinationURL) { _, _ in
                false
            }
        }

        #expect(await session.downloadAttempts.count == 1)
        #expect(try Data(contentsOf: destinationURL) == originalData)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["progress_cancel.jpg"])
    }

    @Test("Download to new destination moves completed .part file cleanly and leaves no file on error")
    func testDownloadToNewDestinationSuccessAndFailureCleanup() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let newURL = dir.appendingPathComponent("fresh.mov")
        let payload = Data("Freshly Downloaded Movie".utf8)
        let successSession = MockSMB2Session { _, _, tempURL, progress in
            try payload.write(to: tempURL)
            _ = progress?(Int64(payload.count), Int64(payload.count))
        }
        let successClient = AMSMB2Client(server: Self.testServer, password: "secret") { _, _ in successSession }
        try await successClient.downloadFile(share: "Media", path: "fresh.mov", to: newURL)
        #expect(try Data(contentsOf: newURL) == payload)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["fresh.mov"])

        let failURL = dir.appendingPathComponent("never_created.mov")
        let failSession = MockSMB2Session { _, _, tempURL, _ in
            try Data("orphan chunk".utf8).write(to: tempURL)
            throw POSIXError(.EIO)
        }
        let failClient = AMSMB2Client(server: Self.testServer, password: "secret") { _, _ in failSession }
        await #expect(throws: SMBError.self) {
            try await failClient.downloadFile(share: "Media", path: "never_created.mov", to: failURL)
        }
        #expect(!FileManager.default.fileExists(atPath: failURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["fresh.mov"])
    }
}
