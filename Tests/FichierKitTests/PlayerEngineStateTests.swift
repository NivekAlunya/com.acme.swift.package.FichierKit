//
//  PlayerEngineStateTests.swift
//  FichierKitTests
//

import Foundation
import Testing
@testable import FichierKit

@Suite("PlayerEngine State Transition Tests")
struct PlayerEngineStateTests {
    @Test("MockPlayerEngine transitions through idle, loading, playing, paused, failed, and tearDown")
    @MainActor
    func mockEngineStateTransitions() {
        let engine: any PlayerEngine = MockPlayerEngine()
        guard let mock = engine as? MockPlayerEngine else {
            Issue.record("Expected MockPlayerEngine")
            return
        }

        #expect(engine.playbackState == .idle)
        #expect(!engine.isPlaying)

        mock.simulateLoading()
        #expect(engine.playbackState == .loading)

        engine.play()
        #expect(engine.playbackState == .playing)
        #expect(engine.isPlaying)

        engine.togglePlayPause()
        #expect(engine.playbackState == .paused)
        #expect(!engine.isPlaying)

        engine.jump(by: 30)
        #expect(engine.currentTime == 30)
        #expect(mock.seekHistory.last?.precision == .fast)

        engine.jump(by: -100)
        #expect(engine.currentTime == 0)

        mock.simulateFailure("Network lost")
        #expect(engine.playbackState == .failed("Network lost"))

        engine.tearDown()
        #expect(engine.playbackState == .idle)
        #expect(engine.currentTime == 0)
    }

    @Test("AVPlayerEngine clamps volume/rate and resets state on tearDown")
    @MainActor
    func avPlayerEngineClampingAndTearDown() {
        let engine = AVPlayerEngine()
        defer { engine.tearDown() }

        #expect(engine.playbackState == .idle)

        engine.volume = 2.5
        #expect(engine.volume == 1.0)
        engine.volume = -0.5
        #expect(engine.volume == 0.0)

        engine.playbackRate = 10.0
        #expect(engine.playbackRate == 4.0)
        engine.playbackRate = 0.05
        #expect(engine.playbackRate == 0.25)
        engine.playbackRate = .nan
        #expect(engine.playbackRate == 0.25)

        var receivedStates: [PlayerPlaybackState] = []
        engine.onStateUpdate = { receivedStates.append($0) }
        engine.clearCallbacks()
        #expect(engine.onStateUpdate == nil)

        engine.tearDown()
        #expect(engine.playbackState == .idle)
        #expect(engine.currentTime == 0)
        #expect(engine.duration == 0)
    }

    @Test("TVVLCPlayerEngine transitions loading -> paused/idle on tearDown")
    @MainActor
    func tvVLCPlayerEngineStateTransitions() {
        let engine = TVVLCPlayerEngine()
        defer { engine.tearDown() }

        #expect(engine.playbackState == .idle)
        engine.load(url: URL(fileURLWithPath: "/tmp/nonexistent_state_test.mkv"), startPosition: 12.0)
        #expect(engine.currentTime == 12.0)

        engine.tearDown()
        #expect(engine.playbackState == .idle)
        #expect(engine.currentTime == 0)
    }
}
