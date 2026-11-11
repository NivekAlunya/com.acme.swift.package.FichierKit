//
//  TVVLCPlayerEngineSeekTests.swift
//  FichierKitTests
//
//

import Foundation
import Testing
@testable import FichierKit
#if canImport(AVFoundation) && canImport(CoreVideo)
import AVFoundation
import CoreVideo
#endif
#if canImport(VLCKit)
import VLCKit
#endif

@Suite("TVVLCPlayerEngine Seek & Settle Tests")
struct TVVLCPlayerEngineSeekTests {
    @Test("TVVLCPlayerEngine resets state and scrubbing flags on tearDown")
    @MainActor
    func testTearDownAndScrubbingStateReset() {
        let engine = TVVLCPlayerEngine()
        defer { engine.tearDown() }

        engine.load(url: URL(fileURLWithPath: "/tmp/nonexistent_seek_check.mkv"), startPosition: 25.0)
        #expect(engine.currentTime == 25.0)

        engine.selectChapter(at: 2)
        #expect(engine.lastSelectedChapterIndex == 2)

        engine.scrub(to: 40.0)
        #expect(engine.isScrubbing == true)
        #expect(engine.currentTime == 40.0)

        engine.endScrubbing(at: 45.0)
        #expect(engine.isScrubbing == false)
        #expect(engine.currentTime == 45.0)

        engine.tearDown()
        #expect(engine.currentTime == 0)
        #expect(engine.playbackPosition == 0)
        #expect(engine.duration == 0)
        #expect(engine.isScrubbing == false)
        #expect(engine.lastSelectedChapterIndex == nil)
        #expect(engine.playbackState == .idle)
    }

    #if canImport(AVFoundation) && canImport(CoreVideo) && canImport(VLCKit)
    @Test("TVVLCPlayerEngine executes live forward, backward, exact, and paused seeks without snapping back")
    @MainActor
    func testLiveFileSeekingAndSettleGuard() async throws {
        let videoURL = try await VideoTestFixtureGenerator.createMultiKeyframeMP4File(seconds: 10)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let engine = TVVLCPlayerEngine()
        engine.isMuted = true
        engine.load(url: videoURL)
        engine.play()
        defer { engine.tearDown() }

        let started = await waitUntil(timeoutSeconds: 6.0) {
            engine.playbackState == .playing && engine.duration >= 9.0 && engine.mediaPlayer.isSeekable
        }
        #expect(started)

        // Forward fast seek (uses b_fast = true under VLCKit 4 with origin-aware settle guard)
        engine.seek(to: 6.0, precision: .fast)
        #expect(abs(engine.currentTime - 6.0) < 0.01)

        try? await Task.sleep(for: .milliseconds(150))
        #expect(engine.currentTime >= 4.0)

        let settledForward = await waitUntil(timeoutSeconds: 3.0) {
            abs(Double(engine.mediaPlayer.time.intValue) / 1000.0 - 6.0) < 2.0
        }
        #expect(settledForward)
        #expect(abs(engine.currentTime - 6.0) < 2.5)

        // Backward fast seek
        engine.seek(to: 2.0, precision: .fast)
        let settledBackward = await waitUntil(timeoutSeconds: 3.0) {
            let playerSec = Double(engine.mediaPlayer.time.intValue) / 1000.0
            return playerSec <= 3.5 && abs(engine.currentTime - 2.0) < 2.0
        }
        #expect(settledBackward)

        // Exact seek
        engine.seek(to: 8.0, precision: .exact)
        let settledExact = await waitUntil(timeoutSeconds: 3.0) {
            abs(Double(engine.mediaPlayer.time.intValue) / 1000.0 - 8.0) < 1.5
        }
        #expect(settledExact)

        // Paused seek + resume
        engine.pause()
        try? await Task.sleep(for: .milliseconds(250))
        engine.seek(to: 4.0, precision: .fast)
        try? await Task.sleep(for: .milliseconds(450))
        #expect(abs(engine.currentTime - 4.0) < 1.5)

        engine.play()
        try? await Task.sleep(for: .milliseconds(350))
        let resumedSec = Double(engine.mediaPlayer.time.intValue) / 1000.0
        #expect(resumedSec >= 3.0 && resumedSec < 6.5)
    }

    @Test("TVVLCPlayerEngine applies deferred startPosition once media becomes seekable")
    @MainActor
    func testDeferredStartPositionSeekAppliesOnceSeekable() async throws {
        let videoURL = try await VideoTestFixtureGenerator.createMultiKeyframeMP4File(seconds: 10)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let engine = TVVLCPlayerEngine()
        engine.isMuted = true
        engine.load(url: videoURL, startPosition: 5.5, options: nil)
        engine.play()
        defer { engine.tearDown() }

        let resumedAtTarget = await waitUntil(timeoutSeconds: 5.0) {
            let playerSec = Double(engine.mediaPlayer.time.intValue) / 1000.0
            return engine.playbackState == .playing && playerSec >= 4.5
        }
        #expect(resumedAtTarget)
        #expect(engine.currentTime >= 4.5)
    }

    @Test("TVVLCPlayerEngine seeks over SMBStreamingServer HTTP loopback and coalesces rapid seeks")
    @MainActor
    func testHTTPLoopbackSeekAndRapidSeekCoalescing() async throws {
        let videoURL = try await VideoTestFixtureGenerator.createMultiKeyframeMP4File(seconds: 10)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let mp4Data = try Data(contentsOf: videoURL)
        let mockClient = RangeOnlyMockSMBClient(files: ["Media/test10s.mp4": mp4Data])
        let server = SMBStreamingServer(
            client: mockClient,
            share: "Media",
            path: "test10s.mp4",
            fileName: "test10s.mp4",
            totalSize: Int64(mp4Data.count)
        )
        let httpURL = try await server.start()
        defer { Task { await server.stop() } }

        let engine = TVVLCPlayerEngine()
        engine.isMuted = true
        engine.load(url: httpURL)
        engine.play()
        defer { engine.tearDown() }

        let started = await waitUntil(timeoutSeconds: 6.0) {
            engine.playbackState == .playing && engine.duration >= 9.0 && engine.mediaPlayer.isSeekable
        }
        #expect(started)

        engine.seek(to: 7.0, precision: .fast)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(engine.currentTime >= 4.5)

        let settledSeven = await waitUntil(timeoutSeconds: 3.0) {
            Double(engine.mediaPlayer.time.intValue) / 1000.0 >= 5.0
        }
        #expect(settledSeven)

        // Rapid sequential seeks settle near the final target
        engine.seek(to: 3.0, precision: .fast)
        try? await Task.sleep(for: .milliseconds(80))
        engine.seek(to: 5.0, precision: .fast)

        let settledFinal = await waitUntil(timeoutSeconds: 3.0) {
            let playerSec = Double(engine.mediaPlayer.time.intValue) / 1000.0
            return abs(playerSec - 5.0) < 2.0 && abs(engine.currentTime - 5.0) < 2.0
        }
        #expect(settledFinal)

        let recordedRanges = await mockClient.recordedRanges
        #expect(recordedRanges.count > 1)
    }

    @Test("TVVLCPlayerEngine jump(by:) and 300ms throttled scrub update currentTime without pausing playback")
    @MainActor
    func testJumpAndThrottledScrubbing() async throws {
        let videoURL = try await VideoTestFixtureGenerator.createMultiKeyframeMP4File(seconds: 10)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let engine = TVVLCPlayerEngine()
        engine.isMuted = true
        engine.load(url: videoURL)
        engine.play()
        defer { engine.tearDown() }

        let started = await waitUntil(timeoutSeconds: 6.0) {
            engine.playbackState == .playing && engine.duration >= 9.0 && engine.mediaPlayer.isSeekable
        }
        #expect(started)

        engine.scrub(to: 5.0)
        #expect(engine.isScrubbing == true)
        #expect(abs(engine.currentTime - 5.0) < 0.01)
        #expect(engine.playbackState == .playing)

        engine.endScrubbing(at: 6.0)
        #expect(engine.isScrubbing == false)
        #expect(abs(engine.currentTime - 6.0) < 0.01)

        engine.jump(by: 2.0)
        #expect(engine.currentTime >= 7.5)
    }

    @MainActor
    private func waitUntil(timeoutSeconds: Double, condition: () -> Bool) async -> Bool {
        let iterations = max(1, Int((timeoutSeconds / 0.05).rounded()))
        for _ in 0..<iterations {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
    #endif
}
