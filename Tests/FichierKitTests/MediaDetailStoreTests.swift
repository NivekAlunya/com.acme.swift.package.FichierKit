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
}
