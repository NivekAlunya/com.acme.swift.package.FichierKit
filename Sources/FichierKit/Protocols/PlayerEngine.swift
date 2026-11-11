//
//  PlayerEngine.swift
//  FichierKit
//

import Foundation

/// Unified playback engine protocol abstracting AVPlayer and VLCKit on tvOS.
///
/// Drives playback, seeking, queue navigation, and audio/subtitle track selection
/// behind a single interface to power the custom Siri Remote overlay.
@MainActor
public protocol PlayerEngine: AnyObject, Sendable {
    /// Current state of media playback.
    var playbackState: PlayerPlaybackState { get }

    /// Indicates whether media is actively advancing.
    var isPlaying: Bool { get }

    /// Current timestamp in seconds.
    var currentTime: Double { get }

    /// Total duration in seconds (0 if unknown or live).
    var duration: Double { get }

    /// Normalized audio output volume in `0.0...1.0`.
    var volume: Double { get set }

    /// Indicates whether audio output is currently muted.
    var isMuted: Bool { get set }

    /// Active playback speed multiplier (default `1.0`).
    var playbackRate: Float { get set }

    /// Available audio tracks discovered for the loaded video.
    var availableAudioTracks: [PlayerAudioTrack] { get }

    /// Currently active audio track, or `nil` if default.
    var selectedAudioTrack: PlayerAudioTrack? { get }

    /// Available subtitle streams, including external or embedded tracks.
    var availableSubtitleTracks: [PlayerSubtitleTrack] { get }

    /// Currently active subtitle track, or `nil` when disabled.
    var selectedSubtitleTrack: PlayerSubtitleTrack? { get }

    /// Embedded chapter markers discovered for the loaded video.
    var availableChapters: [PlayerChapter] { get }

    /// Starts or resumes playback.
    func play()

    /// Suspends playback.
    func pause()

    /// Toggles active playback between play and pause.
    func togglePlayPause()

    /// Seeks to a specific timestamp in seconds using automatic precision scaling.
    func seek(to seconds: Double)

    /// Seeks to a specific timestamp in seconds with explicit decoder keyframe precision.
    func seek(to seconds: Double, precision: PlayerSeekPrecision)

    /// Seeks to a specific timestamp in seconds with explicit tolerance bounds and completion handler.
    func seek(
        to seconds: Double,
        toleranceBefore: Double,
        toleranceAfter: Double,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    )

    /// Jumps forward or backward by the given relative offset in seconds.
    func jump(by deltaSeconds: Double)

    /// Selects an embedded chapter by its index in `availableChapters`.
    func selectChapter(at index: Int)

    /// Advances to the next video item in the playlist.
    func next()

    /// Returns to the previous video item in the playlist.
    func previous()

    /// Switches the active audio track.
    func selectAudioTrack(_ track: PlayerAudioTrack)

    /// Switches the active subtitle track, or passes `nil` to turn subtitles off.
    func selectSubtitleTrack(_ track: PlayerSubtitleTrack?)

    /// Releases hardware decoders and frees streaming buffers.
    func tearDown()
}

public extension PlayerEngine {
    func jump(by deltaSeconds: Double) {
        guard deltaSeconds.isFinite, deltaSeconds != 0 else { return }
        let target = duration > 0
            ? min(max(0, currentTime + deltaSeconds), duration)
            : max(0, currentTime + deltaSeconds)
        seek(to: target, precision: .fast)
    }

    func selectChapter(at index: Int) {
        guard availableChapters.indices.contains(index) else { return }
        seek(to: availableChapters[index].startTime, precision: .exact)
    }
}
