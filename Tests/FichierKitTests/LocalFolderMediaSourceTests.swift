//
//  LocalFolderMediaSourceTests.swift
//  FichierKitTests
//

import Foundation
import Testing
@testable import FichierKit

@Suite("LocalFolderMediaSource Tests")
struct LocalFolderMediaSourceTests {

    private func createTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanupDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Fetch items sorts folders first and paginates accurately")
    func testFetchItemsAndSorting() async throws {
        let root = try createTempDirectory()
        defer { cleanupDirectory(root) }

        // Create 2 folders and 3 files
        let bFolder = root.appendingPathComponent("B_Folder")
        try FileManager.default.createDirectory(at: bFolder, withIntermediateDirectories: true)
        let aFolder = root.appendingPathComponent("A_Folder")
        try FileManager.default.createDirectory(at: aFolder, withIntermediateDirectories: true)
        try Data("img".utf8).write(to: root.appendingPathComponent("Z_photo.jpg"))
        try Data("vid".utf8).write(to: root.appendingPathComponent("M_video.mp4"))
        try Data("img2".utf8).write(to: root.appendingPathComponent("A_photo.png"))

        let source = LocalFolderMediaSource(rootURL: root)

        // Page 0 with pageSize 3 (should return A_Folder, B_Folder, and A_photo.png)
        let page0 = try await source.fetchItems(in: nil, sortBy: .name, order: .ascending, page: 0, pageSize: 3)
        #expect(page0.count == 3)
        #expect(page0[0].name == "A_Folder")
        #expect(page0[0].type == .folder)
        #expect(page0[1].name == "B_Folder")
        #expect(page0[1].type == .folder)
        #expect(page0[2].name == "A_photo.png")
        #expect(page0[2].type == .image)

        // Page 1 with pageSize 3 (should return M_video.mp4 and Z_photo.jpg)
        let page1 = try await source.fetchItems(in: nil, sortBy: .name, order: .ascending, page: 1, pageSize: 3)
        #expect(page1.count == 2)
        #expect(page1[0].name == "M_video.mp4")
        #expect(page1[0].type == .video)
        #expect(page1[1].name == "Z_photo.jpg")
        #expect(page1[1].type == .image)
    }

    @Test("Create folder succeeds and enforces path sanitization")
    func testCreateFolder() async throws {
        let root = try createTempDirectory()
        defer { cleanupDirectory(root) }

        let source = LocalFolderMediaSource(rootURL: root)

        let created = try await source.createFolder(named: "NewDir")
        #expect(created.name == "NewDir")
        #expect(created.type == .folder)
        #expect(FileManager.default.fileExists(atPath: created.localURL!.path))

        // Duplicate name
        await #expect(throws: FileOperationError.self) {
            try await source.createFolder(named: "NewDir")
        }

        // Invalid characters
        await #expect(throws: FileOperationError.self) {
            try await source.createFolder(named: "Bad/Slash")
        }
        await #expect(throws: FileOperationError.self) {
            try await source.createFolder(named: "Bad\\Backslash")
        }
        await #expect(throws: FileOperationError.self) {
            try await source.createFolder(named: "Bad:Colon")
        }
        await #expect(throws: FileOperationError.self) {
            try await source.createFolder(named: "..")
        }
    }

    @Test("Rename item handles APFS case-only renames and collisions")
    func testRenameItem() async throws {
        let root = try createTempDirectory()
        defer { cleanupDirectory(root) }

        let fileURL = root.appendingPathComponent("lowercase.txt")
        try Data("sample".utf8).write(to: fileURL)

        let source = LocalFolderMediaSource(rootURL: root)
        let item = MediaSourceItem(
            id: "\(source.id)::lowercase.txt",
            name: "lowercase.txt",
            path: "lowercase.txt",
            type: .image,
            localURL: fileURL,
            sourceID: source.id
        )

        // Case-only rename
        let renamed = try await source.renameItem(item, to: "Lowercase.txt")
        #expect(renamed.name == "Lowercase.txt")
        #expect(renamed.path == "Lowercase.txt")
        #expect(FileManager.default.fileExists(atPath: renamed.localURL!.path))

        // Collision check
        let secondURL = root.appendingPathComponent("existing.txt")
        try Data("other".utf8).write(to: secondURL)

        await #expect(throws: FileOperationError.self) {
            try await source.renameItem(renamed, to: "existing.txt")
        }
    }

    @Test("Move items moves cleanly and prevents moving into self")
    func testMoveItems() async throws {
        let root = try createTempDirectory()
        defer { cleanupDirectory(root) }

        let subDirURL = root.appendingPathComponent("TargetDir")
        try FileManager.default.createDirectory(at: subDirURL, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("file.png")
        try Data("data".utf8).write(to: fileURL)

        let source = LocalFolderMediaSource(rootURL: root)
        let fileItem = MediaSourceItem(
            id: "\(source.id)::file.png",
            name: "file.png",
            path: "file.png",
            type: .image,
            localURL: fileURL,
            sourceID: source.id
        )
        let destItem = MediaSourceItem(
            id: "\(source.id)::TargetDir",
            name: "TargetDir",
            path: "TargetDir",
            type: .folder,
            localURL: subDirURL,
            sourceID: source.id
        )

        try await source.moveItems([fileItem], to: destItem)
        let movedURL = subDirURL.appendingPathComponent("file.png")
        #expect(FileManager.default.fileExists(atPath: movedURL.path))
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        // Cannot move directory into itself
        await #expect(throws: FileOperationError.self) {
            try await source.moveItems([destItem], to: destItem)
        }
    }

    @Test("Delete items removes items from disk")
    func testDeleteItems() async throws {
        let root = try createTempDirectory()
        defer { cleanupDirectory(root) }

        let fileURL = root.appendingPathComponent("to_delete.jpg")
        try Data("bytes".utf8).write(to: fileURL)

        let source = LocalFolderMediaSource(rootURL: root)
        let item = MediaSourceItem(
            id: "\(source.id)::to_delete.jpg",
            name: "to_delete.jpg",
            path: "to_delete.jpg",
            type: .image,
            localURL: fileURL,
            sourceID: source.id
        )

        try await source.deleteItems([item])
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }
}
