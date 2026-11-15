//
//  SMBFileOperationsTests.swift
//  FichierKitTests
//
//

import Foundation
import Testing
@testable import FichierKit

@Suite("SMB File Operations & Sanitization Tests")
struct SMBFileOperationsTests {
    private let testServer = SavedSMBConnection(
        host: "192.168.1.100",
        username: "user",
        lastConnected: Date()
    )

    @Test("createDirectory creates directory, normalizes path, and clears cached snapshot")
    func testCreateDirectorySuccess() async throws {
        let mockSession = MockSMB2Session()
        let client = AMSMB2Client(server: testServer, password: "pwd") { _, _ in
            mockSession
        }

        try await client.createDirectory(share: "Media", path: "/Subfolder/NewFolder/")
        let created = await mockSession.createdDirectories
        #expect(created == ["Subfolder/NewFolder"])
    }

    @Test("createDirectory rejects invalid names and path traversal")
    func testCreateDirectoryRejectsInvalidNames() async throws {
        let mockSession = MockSMB2Session()
        let client = AMSMB2Client(server: testServer, password: "pwd") { _, _ in
            mockSession
        }

        // Empty path
        await #expect(throws: FileOperationError.self) {
            try await client.createDirectory(share: "Media", path: "")
        }

        // Root/slash only
        await #expect(throws: FileOperationError.self) {
            try await client.createDirectory(share: "Media", path: "///")
        }

        // Traversal ..
        await #expect(throws: FileOperationError.self) {
            try await client.createDirectory(share: "Media", path: "Folder/../Other")
        }

        // Colon in name
        await #expect(throws: FileOperationError.self) {
            try await client.createDirectory(share: "Media", path: "Invalid:Name")
        }
    }

    @Test("createDirectory maps EEXIST POSIX error to itemAlreadyExists")
    func testCreateDirectoryDuplicateError() async throws {
        let mockSession = MockSMB2Session()
        await mockSession.setOnCreateDirectory { _ in
            throw POSIXError(.EEXIST)
        }
        let client = AMSMB2Client(server: testServer, password: "pwd") { _, _ in
            mockSession
        }

        do {
            try await client.createDirectory(share: "Media", path: "ExistingFolder")
            Issue.record("Expected FileOperationError.itemAlreadyExists")
        } catch let error as FileOperationError {
            switch error {
            case .itemAlreadyExists(let name):
                #expect(name == "ExistingFolder")
            default:
                Issue.record("Expected .itemAlreadyExists, got \(error)")
            }
        }
    }

    @Test("removeItem successfully removes item and normalizes path")
    func testRemoveItemSuccess() async throws {
        let mockSession = MockSMB2Session()
        let client = AMSMB2Client(server: testServer, password: "pwd") { _, _ in
            mockSession
        }

        try await client.removeItem(share: "Media", path: "/Folder/delete_me.jpg/")
        let removed = await mockSession.removedItems
        #expect(removed == ["Folder/delete_me.jpg"])
    }

    @Test("removeItem rejects traversal inputs")
    func testRemoveItemRejectsTraversal() async throws {
        let mockSession = MockSMB2Session()
        let client = AMSMB2Client(server: testServer, password: "pwd") { _, _ in
            mockSession
        }

        await #expect(throws: FileOperationError.self) {
            try await client.removeItem(share: "Media", path: "../escape.txt")
        }
    }

    @Test("moveItem successfully moves item across directory paths")
    func testMoveItemSuccess() async throws {
        let mockSession = MockSMB2Session()
        let client = AMSMB2Client(server: testServer, password: "pwd") { _, _ in
            mockSession
        }

        try await client.moveItem(share: "Media", fromPath: "Source/photo.jpg", toPath: "Target/photo.jpg")
        let moved = await mockSession.movedItems
        #expect(moved.count == 1)
        #expect(moved.first?.from == "Source/photo.jpg")
        #expect(moved.first?.to == "Target/photo.jpg")
    }

    @Test("moveItem prevents moving into self or nested subfolder")
    func testMoveItemPreventsMovingIntoSelf() async throws {
        let mockSession = MockSMB2Session()
        let client = AMSMB2Client(server: testServer, password: "pwd") { _, _ in
            mockSession
        }

        // Move folder directly into self
        await #expect(throws: FileOperationError.self) {
            try await client.moveItem(share: "Media", fromPath: "MyFolder", toPath: "MyFolder")
        }

        // Move folder into its own subfolder
        await #expect(throws: FileOperationError.self) {
            try await client.moveItem(share: "Media", fromPath: "MyFolder", toPath: "MyFolder/Sub")
        }
    }

    @Test("MockSMBClient tracks in-memory mutations accurately")
    func testMockSMBClientMutations() async throws {
        let initialItem = MediaSourceItem(
            id: "Media::/file.jpg",
            name: "file.jpg",
            path: "Media/file.jpg",
            type: .image,
            size: 100,
            smbShare: "Media",
            smbPath: "file.jpg"
        )
        let client = MockSMBClient(mockShares: ["Media"], mockItems: [initialItem], mockFileData: ["Media/file.jpg": Data([1, 2, 3])])

        try await client.createDirectory(share: "Media", path: "Photos")
        #expect(client.createdDirectories.count == 1)
        #expect(client.createdDirectories.first?.path == "Photos")

        try await client.moveItem(share: "Media", fromPath: "file.jpg", toPath: "Photos/file.jpg")
        #expect(client.movedItems.count == 1)
        let itemsAfterMove = try await client.listDirectory(share: "Media", path: "")
        #expect(itemsAfterMove.contains { $0.smbPath == "Photos/file.jpg" })

        try await client.removeItem(share: "Media", path: "Photos/file.jpg")
        #expect(client.removedItems.count == 1)
        let itemsAfterRemove = try await client.listDirectory(share: "Media", path: "")
        #expect(!itemsAfterRemove.contains { $0.smbPath == "Photos/file.jpg" })
    }
}

private extension MockSMB2Session {
    func setOnCreateDirectory(_ handler: @escaping @Sendable (String) async throws -> Void) {
        self.onCreateDirectory = handler
    }
}
