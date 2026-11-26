//
//  MockPlayerEngine.swift
//  FichierKitTests
//

import Foundation
@testable import FichierKit

/// Protocol-backed `PlayerEngine` test double for verifying playback state transitions without AVPlayer/VLCKit.
@MainActor
final class MockPlayerEngine: PlayerEngine {
    private(set) var playbackState: PlayerPlaybackState = .idle
    private(set) var isPlaying: Bool = false
    private(set) var currentTime: Double = 0
    var duration: Double = 120
    var volume: Double = 1.0
    var isMuted: Bool = false
    var playbackRate: Float = 1.0

    var availableAudioTracks: [PlayerAudioTrack] = []
    var selectedAudioTrack: PlayerAudioTrack?
    var availableSubtitleTracks: [PlayerSubtitleTrack] = []
    var selectedSubtitleTrack: PlayerSubtitleTrack?
    var availableChapters: [PlayerChapter] = []

    private(set) var seekHistory: [(seconds: Double, precision: PlayerSeekPrecision)] = []
    private(set) var nextCount = 0
    private(set) var previousCount = 0
    private(set) var tearDownCount = 0
    private(set) var clearCallbacksCount = 0

    func simulateLoading() {
        playbackState = .loading
        isPlaying = false
    }

    func simulateReady() {
        playbackState = .paused
    }

    func simulateFailure(_ message: String) {
        playbackState = .failed(message)
        isPlaying = false
    }

    func play() {
        isPlaying = true
        playbackState = .playing
    }

    func pause() {
        isPlaying = false
        playbackState = .paused
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to seconds: Double) {
        seek(to: seconds, precision: .automatic)
    }

    func seek(to seconds: Double, precision: PlayerSeekPrecision) {
        seekHistory.append((seconds, precision))
        currentTime = min(max(0, seconds), duration)
    }

    func seek(
        to seconds: Double,
        toleranceBefore: Double,
        toleranceAfter: Double,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        seek(to: seconds, precision: .exact)
        completion?(true)
    }

    func next() {
        nextCount += 1
    }

    func previous() {
        previousCount += 1
    }

    func selectAudioTrack(_ track: PlayerAudioTrack) {
        selectedAudioTrack = track
    }

    func selectSubtitleTrack(_ track: PlayerSubtitleTrack?) {
        selectedSubtitleTrack = track
    }

    func tearDown() {
        tearDownCount += 1
        isPlaying = false
        currentTime = 0
        playbackState = .idle
    }

    func clearCallbacks() {
        clearCallbacksCount += 1
    }
}
