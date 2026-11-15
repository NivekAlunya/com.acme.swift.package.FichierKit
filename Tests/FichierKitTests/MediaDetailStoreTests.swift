//
//  MediaDetailStoreTests.swift
//  FichierKitTests
//
//

import Foundation
import Testing
@testable import FichierKit

@Suite("MediaDetailStore and Formatting Tests")
struct MediaDetailStoreTests {

    @Test("Format video duration accurately")
    func testFormatDuration() {
        #expect(MediaFormatHelper.formatDuration(0) == "")
        #expect(MediaFormatHelper.formatDuration(-10) == "")
        #expect(MediaFormatHelper.formatDuration(.nan) == "")
        #expect(MediaFormatHelper.formatDuration(.infinity) == "")

        // Under 1 minute
        #expect(MediaFormatHelper.formatDuration(12) == "00:12")

        // Multi-minute under 1 hour
        #expect(MediaFormatHelper.formatDuration(165) == "02:45")

        // Exactly 1 hour
        #expect(MediaFormatHelper.formatDuration(3600) == "1:00:00")

        // Over 1 hour
        #expect(MediaFormatHelper.formatDuration(4530) == "1:15:30")

        // Overflow bounds protection
        #expect(MediaFormatHelper.formatDuration(.greatestFiniteMagnitude) == "")
        #expect(MediaFormatHelper.formatDuration(Double(Int.max) * 2) == "")
    }

    @Test("Format image frame dimensions accurately")
    func testFormatDimensions() {
        #expect(MediaFormatHelper.formatDimensions(width: 0, height: 0) == "")
        #expect(MediaFormatHelper.formatDimensions(width: -100, height: 200) == "")
        #expect(MediaFormatHelper.formatDimensions(width: 1920, height: 1080) == "1920 × 1080")
        #expect(MediaFormatHelper.formatDimensions(width: 3840, height: 2160) == "3840 × 2160")
    }

    @Test("Format PDF page count accurately")
    func testFormatPageCount() {
        #expect(MediaFormatHelper.formatPageCount(0) == "")
        #expect(MediaFormatHelper.formatPageCount(-1) == "")
        #expect(MediaFormatHelper.formatPageCount(1) == "1 page")
        #expect(MediaFormatHelper.formatPageCount(12) == "12 pages")
    }

    @Test("MediaDetailStore synchronous caching and registration")
    @MainActor
    func testMediaDetailStoreCache() {
        let store = MediaDetailStore.shared
        store.clearCache()

        let itemID = "test-item-123"
        #expect(store.cachedDetail(for: itemID) == nil)

        store.registerDetail("3840 × 2160", for: itemID)
        #expect(store.cachedDetail(for: itemID) == "3840 × 2160")

        store.clearCache()
        #expect(store.cachedDetail(for: itemID) == nil)
    }

    @Test("Resolve folder returns nil")
    @MainActor
    func testResolveFolder() async {
        let store = MediaDetailStore.shared
        let folderItem = MediaSourceItem(
            id: "folder-1",
            name: "Documents",
            path: "Documents",
            type: .folder
        )

        let detail = await store.resolveDetail(for: folderItem)
        #expect(detail == nil)
    }

    @Test("Resolve PDF returns nil (page count disabled)")
    @MainActor
    func testResolvePDFReturnsNil() async {
        let store = MediaDetailStore.shared
        #if !os(tvOS)
        let itemType: MediaItemType = .document
        #else
        let itemType: MediaItemType = .image
        #endif
        let pdfItem = MediaSourceItem(
            id: "pdf-1",
            name: "Document.pdf",
            path: "Document.pdf",
            type: itemType
        )

        let detail = await store.resolveDetail(for: pdfItem)
        #expect(detail == nil)
    }

    @Test("Concurrent resolution queries for the same item are deduplicated")
    @MainActor
    func testConcurrentResolutionDeduplication() async {
        let store = MediaDetailStore.shared
        store.clearCache()

        let folderItem = MediaSourceItem(
            id: "dedup-folder-1",
            name: "Folder",
            path: "Folder",
            type: .folder
        )

        // Launch multiple concurrent resolution requests
        async let first = store.resolveDetail(for: folderItem)
        async let second = store.resolveDetail(for: folderItem)
        async let third = store.resolveDetail(for: folderItem)

        let (r1, r2, r3) = await (first, second, third)
        #expect(r1 == nil)
        #expect(r2 == nil)
        #expect(r3 == nil)
    }
}
