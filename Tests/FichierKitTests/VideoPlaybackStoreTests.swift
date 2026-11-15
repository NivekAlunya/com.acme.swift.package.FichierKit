//
//  VideoPlaybackStoreTests.swift
//  FichierKitTests
//

import Foundation
import Testing
@testable import FichierKit

@Suite("VideoPlaybackStore Tests")
struct VideoPlaybackStoreTests {
    private struct TestContext {
        let store: VideoPlaybackStore
        let defaults: UserDefaults
        let suiteName: String
    }

    private func makeCleanStore() -> TestContext {
        let suiteName = "VideoPlaybackStoreTests_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = VideoPlaybackStore(userDefaults: defaults)
        return TestContext(store: store, defaults: defaults, suiteName: suiteName)
    }

    @Test("Verify VideoPlaybackRecord properties and progress calculation")
    func testRecordProgress() {
        let record = VideoPlaybackRecord(position: 50.0, duration: 100.0)
        #expect(record.progress == 0.5)
        #expect(!record.isFinished)

        let zeroDurationRecord = VideoPlaybackRecord(position: 10.0, duration: 0)
        #expect(zeroDurationRecord.progress == 0.0)

        let clampedRecord = VideoPlaybackRecord(position: 120.0, duration: 100.0)
        #expect(clampedRecord.progress == 1.0)

        let nanRecord = VideoPlaybackRecord(position: Double.nan, duration: 100.0)
        #expect(nanRecord.progress == 0.0)

        let infRecord = VideoPlaybackRecord(position: 10.0, duration: Double.infinity)
        #expect(infRecord.progress == 0.0)
    }

    @Test("Verify savePosition ignores invalid inputs under 2 seconds")
    @MainActor
    func testSavePositionIgnoresShortPlayback() {
        let ctx = makeCleanStore()

        ctx.store.savePosition(1.5, duration: 100.0, for: "item-1")
        #expect(ctx.store.status(for: "item-1") == .unwatched)
        #expect(ctx.store.position(for: "item-1") == nil)

        ctx.store.savePosition(Double.nan, duration: 100.0, for: "item-1")
        #expect(ctx.store.status(for: "item-1") == .unwatched)

        ctx.store.savePosition(10.0, duration: Double.infinity, for: "item-1")
        #expect(ctx.store.status(for: "item-1") == .unwatched)
    }

    @Test("Verify in-progress tracking and resume position")
    @MainActor
    func testInProgressTracking() {
        let ctx = makeCleanStore()

        ctx.store.savePosition(30.0, duration: 120.0, for: "item-2")
        #expect(ctx.store.status(for: "item-2") == .inProgress(progress: 0.25))
        #expect(ctx.store.position(for: "item-2") == 30.0)

        ctx.store.savePosition(60.0, duration: 120.0, for: "item-2")
        #expect(ctx.store.position(for: "item-2") == 60.0)
    }

    @Test("Verify automatic completion detection near end of video")
    @MainActor
    func testAutomaticCompletion() {
        let ctx = makeCleanStore()

        // At 90% watched
        ctx.store.savePosition(92.0, duration: 100.0, for: "item-3")
        #expect(ctx.store.status(for: "item-3") == .finished)
        #expect(ctx.store.position(for: "item-3") == nil)

        // Within final 4s for videos > 15s
        ctx.store.savePosition(57.0, duration: 60.0, for: "item-4")
        #expect(ctx.store.status(for: "item-4") == .finished)
        #expect(ctx.store.position(for: "item-4") == nil)
    }

    @Test("Verify clearPosition removes in-memory and persisted records")
    @MainActor
    func testClearPosition() {
        let ctx = makeCleanStore()

        ctx.store.savePosition(40.0, duration: 100.0, for: "item-5")
        #expect(ctx.store.status(for: "item-5") == .inProgress(progress: 0.4))

        ctx.store.clearPosition(for: "item-5")
        #expect(ctx.store.status(for: "item-5") == .unwatched)
        #expect(ctx.store.position(for: "item-5") == nil)
    }

    @Test("Verify VideoPlaybackStoreProtocol async conformance")
    @MainActor
    func testProtocolConformance() async {
        let ctx = makeCleanStore()
        let protocolStore: any VideoPlaybackStoreProtocol = ctx.store

        await protocolStore.savePlaybackPosition(itemID: "proto-1", time: 45.0, duration: 100.0)
        let pos = await protocolStore.playbackPosition(for: "proto-1")
        #expect(pos == 45.0)

        await protocolStore.clearPlaybackPosition(for: "proto-1")
        let clearedPos = await protocolStore.playbackPosition(for: "proto-1")
        #expect(clearedPos == nil)
    }

    @Test("Verify MediaSourceItem helper methods")
    @MainActor
    func testMediaSourceItemHelpers() {
        let ctx = makeCleanStore()
        let sourceItem = MediaSourceItem(
            id: "smb-item-1",
            name: "movie.mp4",
            path: "Videos/movie.mp4",
            type: .video,
            size: 1024,
            smbShare: "Videos",
            smbPath: "movie.mp4"
        )

        ctx.store.savePosition(25.0, duration: 100.0, for: sourceItem)
        #expect(ctx.store.status(for: sourceItem) == .inProgress(progress: 0.25))
        #expect(ctx.store.position(for: sourceItem) == 25.0)

        ctx.store.markFinished(for: sourceItem)
        #expect(ctx.store.status(for: sourceItem) == .finished)
        #expect(ctx.store.position(for: sourceItem) == nil)

        ctx.store.clearPosition(for: sourceItem)
        #expect(ctx.store.status(for: sourceItem) == .unwatched)
    }

    @Test("Verify persistence and reload across store instances")
    @MainActor
    func testPersistenceAcrossInstances() {
        let ctx = makeCleanStore()
        defer { ctx.defaults.removePersistentDomain(forName: ctx.suiteName) }

        ctx.store.savePosition(50.0, duration: 200.0, for: "persist-1")
        ctx.store.flush()

        // Create a new store instance using the same defaults
        let store2 = VideoPlaybackStore(userDefaults: ctx.defaults)
        #expect(store2.status(for: "persist-1") == .inProgress(progress: 0.25))
        #expect(store2.position(for: "persist-1") == 50.0)
    }
}
