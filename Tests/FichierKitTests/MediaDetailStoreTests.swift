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

    @Test("Format timestamp clock strings accurately")
    func testFormatTimestamp() {
        #expect(MediaFormatHelper.formatTimestamp(0) == "00:00")
        #expect(MediaFormatHelper.formatTimestamp(0, zeroPaddedMinutes: false) == "0:00")
        #expect(MediaFormatHelper.formatTimestamp(-5) == "00:00")
        #expect(MediaFormatHelper.formatTimestamp(.nan) == "00:00")

        #expect(MediaFormatHelper.formatTimestamp(12) == "00:12")
        #expect(MediaFormatHelper.formatTimestamp(12, zeroPaddedMinutes: false) == "0:12")

        #expect(MediaFormatHelper.formatTimestamp(83, zeroPaddedMinutes: false) == "1:23")
        #expect(MediaFormatHelper.formatTimestamp(83, zeroPaddedMinutes: true) == "01:23")

        #expect(MediaFormatHelper.formatTimestamp(3665, zeroPaddedHours: true) == "01:01:05")
        #expect(MediaFormatHelper.formatTimestamp(3665, zeroPaddedHours: false, zeroPaddedMinutes: false) == "1:01:05")
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

    @Test("Parse duration handles valid and invalid inputs safely")
    func testParseDurationEdgeCases() {
        // Valid inputs
        #expect(MediaFormatHelper.parseDuration("00:00") == 0.0)
        #expect(MediaFormatHelper.parseDuration("02:45") == 165.0)
        #expect(MediaFormatHelper.parseDuration("1:15:30") == 4530.0)
        #expect(MediaFormatHelper.parseDuration("  03:10  ") == 190.0)

        // Invalid inputs that must return nil without traps
        #expect(MediaFormatHelper.parseDuration("NaN") == nil)
        #expect(MediaFormatHelper.parseDuration("inf") == nil)
        #expect(MediaFormatHelper.parseDuration("Infinity") == nil)
        #expect(MediaFormatHelper.parseDuration("-05:00") == nil)
        #expect(MediaFormatHelper.parseDuration("02::45") == nil)
        #expect(MediaFormatHelper.parseDuration(":02:45") == nil)
        #expect(MediaFormatHelper.parseDuration("02:45:") == nil)
        #expect(MediaFormatHelper.parseDuration("1:2:3:4") == nil)
        #expect(MediaFormatHelper.parseDuration("") == nil)
        #expect(MediaFormatHelper.parseDuration("invalid") == nil)
    }

    @Test("Parse dimensions handles valid and invalid inputs safely")
    func testParseDimensionsEdgeCases() {
        // Valid inputs with unicode cross and ascii x
        let d1 = MediaFormatHelper.parseDimensions("3840 × 2160")
        #expect(d1?.width == 3840 && d1?.height == 2160)

        let d2 = MediaFormatHelper.parseDimensions("1920 x 1080")
        #expect(d2?.width == 1920 && d2?.height == 1080)

        // Invalid inputs
        #expect(MediaFormatHelper.parseDimensions("0 × 100") == nil)
        #expect(MediaFormatHelper.parseDimensions("100 × 0") == nil)
        #expect(MediaFormatHelper.parseDimensions("-100 × 200") == nil)
        #expect(MediaFormatHelper.parseDimensions("NaN × 100") == nil)
        #expect(MediaFormatHelper.parseDimensions("3840") == nil)
        #expect(MediaFormatHelper.parseDimensions("") == nil)
        #expect(MediaFormatHelper.parseDimensions("invalid") == nil)
    }

    @Test("MediaDetailStore caches parsed numeric resolution and duration")
    @MainActor
    func testMediaDetailStoreNumericCaching() {
        let store = MediaDetailStore.shared
        store.clearCache()

        let imgID = "img-item"
        let vidID = "vid-item"

        store.registerDetail("3840 × 2160", for: imgID)
        #expect(store.resolution(for: imgID) == 3840 * 2160)
        #expect(store.dimensions(for: imgID)?.width == 3840)
        #expect(store.duration(for: imgID) == nil)

        store.registerDetail("02:30", for: vidID)
        #expect(store.duration(for: vidID) == 150.0)
        #expect(store.resolution(for: vidID) == nil)

        store.clearCache()
        #expect(store.resolution(for: imgID) == nil)
        #expect(store.duration(for: vidID) == nil)
    }

    @Test("MediaDetailStore prevents integer overflow and clears stale numeric caches")
    @MainActor
    func testMediaDetailStoreOverflowAndCacheConsistency() {
        let store = MediaDetailStore.shared
        store.clearCache()

        let itemID = "multimedia-item"

        // 1. Initial registration with resolution (image)
        store.registerDetail("1920 × 1080", for: itemID)
        #expect(store.resolution(for: itemID) == 1920 * 1080)
        #expect(store.duration(for: itemID) == nil)

        // 2. Overwrite with duration (e.g. item re-classified as video): resolution cache must be cleared
        store.registerDetail("01:30", for: itemID)
        #expect(store.cachedDetail(for: itemID) == "01:30")
        #expect(store.resolution(for: itemID) == nil)
        #expect(store.duration(for: itemID) == 90.0)

        // 3. Overwrite with document page count: duration cache must also be cleared
        store.registerDetail("12 pages", for: itemID)
        #expect(store.cachedDetail(for: itemID) == "12 pages")
        #expect(store.resolution(for: itemID) == nil)
        #expect(store.duration(for: itemID) == nil)

        // 4. Overflow protection: dimensions that exceed Int bounds must not trap and return nil
        let overflowID = "overflow-item"
        store.registerDetail("\(Int.max) × 2", for: overflowID)
        #expect(store.resolution(for: overflowID) == nil)
    }

    @Test("MediaSortKey CaseIterable and Codable round-trip")
    func testMediaSortKeyCodable() throws {
        #expect(MediaSortKey.allCases.count == 7)
        #expect(MediaSortKey.allCases == [.name, .date, .size, .type, .kind, .resolution, .duration])

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for key in MediaSortKey.allCases {
            let data = try encoder.encode(key)
            let decoded = try decoder.decode(MediaSortKey.self, from: data)
            #expect(decoded == key)
        }
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
