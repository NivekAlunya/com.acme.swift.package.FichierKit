//
//  MediaDiskCacheActorTests.swift
//  FichierKitTests
//

import Foundation
import Testing
@testable import FichierKit

@Suite("MediaDiskCacheActor Tests")
struct MediaDiskCacheActorTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaDiskCacheActorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("writeData and readData round-trip binary payload")
    func writeAndReadRoundTrip() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let actor = MediaDiskCacheActor()
        let targetURL = tempDir.appendingPathComponent("nested/sample.bin")
        let payload = Data([0x01, 0x02, 0x03, 0x04])

        #expect(await actor.readData(from: targetURL) == nil)
        try await actor.writeData(payload, to: targetURL)
        #expect(await actor.readData(from: targetURL) == payload)
    }

    @Test("migrateFile moves source to destination and removes duplicate source if destination exists")
    func migrateFileBehavior() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let actor = MediaDiskCacheActor()
        let legacyURL = tempDir.appendingPathComponent("legacy.jpg")
        let newURL = tempDir.appendingPathComponent("sub/new.jpg")
        let legacyData = Data("legacy".utf8)
        let newData = Data("new".utf8)

        try await actor.writeData(legacyData, to: legacyURL)
        await actor.migrateFile(from: legacyURL, to: newURL)

        #expect(await actor.readData(from: legacyURL) == nil)
        #expect(await actor.readData(from: newURL) == legacyData)

        // When destination already exists, legacy duplicate should be purged without overwriting destination.
        try await actor.writeData(newData, to: newURL)
        try await actor.writeData(legacyData, to: legacyURL)
        await actor.migrateFile(from: legacyURL, to: newURL)

        #expect(await actor.readData(from: legacyURL) == nil)
        #expect(await actor.readData(from: newURL) == newData)
    }

    @Test("filterExistingFiles returns only URLs present on disk")
    func filterExistingFilesReturnsPresentURLs() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let actor = MediaDiskCacheActor()
        let existingURL = tempDir.appendingPathComponent("present.dat")
        let missingURL = tempDir.appendingPathComponent("missing.dat")
        try await actor.writeData(Data([0xAA]), to: existingURL)

        let filtered = await actor.filterExistingFiles(among: [existingURL, missingURL])
        #expect(filtered == [existingURL])
    }
}
