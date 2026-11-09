//
//  TVVLCPlayerEngine.swift
//  FichierKit
//
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(VLCKit)
import VLCKit
#endif

/// Extended playback engine leveraging `VLCKit` (VideoLAN LibVLC) for non-native video containers and codecs.
@MainActor
public final class TVVLCPlayerEngine: NSObject, PlayerEngine {
    public private(set) var playbackState: PlayerPlaybackState = .idle {
        didSet {
            if playbackState != oldValue {
                onStateUpdate?(playbackState)
            }
        }
    }

    public private(set) var currentTime: Double = 0 {
        didSet {
            onTimeUpdate?(currentTime)
        }
    }

    public private(set) var duration: Double = 0 {
        didSet {
            if duration != oldValue {
                onDurationUpdate?(duration)
            }
        }
    }

    public private(set) var availableAudioTracks: [PlayerAudioTrack] = []
    public private(set) var selectedAudioTrack: PlayerAudioTrack?
    public private(set) var availableSubtitleTracks: [PlayerSubtitleTrack] = []
    public private(set) var selectedSubtitleTrack: PlayerSubtitleTrack?
    public private(set) var availableChapters: [PlayerChapter] = []

    public var isPlaying: Bool {
        #if canImport(VLCKit)
        return mediaPlayer.isPlaying || playbackState == .playing
        #else
        return playbackState == .playing
        #endif
    }

    public var volume: Double {
        get { volumeInternal }
        set {
            volumeInternal = max(0.0, min(1.0, newValue))
            #if canImport(VLCKit)
            mediaPlayer.audio?.volume = Int32(volumeInternal * 100.0)
            #endif
        }
    }

    public var isMuted: Bool {
        get { isMutedInternal }
        set {
            isMutedInternal = newValue
            #if canImport(VLCKit)
            mediaPlayer.audio?.isMuted = newValue
            #endif
        }
    }

    public var playbackRate: Float = 1.0 {
        didSet {
            let clamped = max(0.25, min(4.0, playbackRate))
            if playbackRate != clamped {
                playbackRate = clamped
                return
            }
            #if canImport(VLCKit)
            mediaPlayer.rate = clamped
            #endif
        }
    }

    public var onPlaybackEnded: (@MainActor @Sendable () -> Void)?
    public var onError: (@MainActor @Sendable (Error) -> Void)?
    public var onStateUpdate: (@MainActor @Sendable (PlayerPlaybackState) -> Void)?
    public var onTimeUpdate: (@MainActor @Sendable (Double) -> Void)?
    public var onDurationUpdate: (@MainActor @Sendable (Double) -> Void)?
    public var onTracksChanged: (@MainActor @Sendable () -> Void)?
    public var onChaptersChanged: (@MainActor @Sendable () -> Void)?

    #if canImport(UIKit)
    /// Underlying UIKit drawable view attached to `VLCMediaPlayer.drawable`.
    public let renderView: UIView = {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        return view
    }()
    #endif

    #if canImport(VLCKit)
    public let mediaPlayer = VLCMediaPlayer()
    private var audioTrackByID: [String: VLCMediaPlayer.Track] = [:]
    private var subtitleTrackByID: [String: VLCMediaPlayer.Track] = [:]
    #endif

    private var volumeInternal: Double = 1.0
    private var isMutedInternal: Bool = false
    private var pendingSeekSeconds: Double?
    private var lastKnownAudioTrackCount: Int = -1
    private var lastKnownSubtitleTrackCount: Int = -1
    private var lastKnownChapterSignature: String = ""
    private var hasReportedTerminalFailure: Bool = false
    private var isExplicitStop: Bool = false
    private var didStartPlayback: Bool = false
    private var didEmitPlaybackEnded: Bool = false

    public override init() {
        super.init()
        #if canImport(VLCKit)
        mediaPlayer.delegate = self
        #if canImport(UIKit)
        mediaPlayer.drawable = renderView
        #endif
        #endif
    }

    /// Re-attaches the drawable render surface to LibVLC.
    public func attachDrawable() {
        #if canImport(VLCKit) && canImport(UIKit)
        mediaPlayer.drawable = renderView
        #endif
    }

    /// Loads a media URL for playback through the VLC pipeline.
    public func load(url: URL) {
        isExplicitStop = true
        didStartPlayback = false
        didEmitPlaybackEnded = false
        hasReportedTerminalFailure = false
        pendingSeekSeconds = nil
        lastKnownAudioTrackCount = -1
        lastKnownSubtitleTrackCount = -1
        lastKnownChapterSignature = ""
        currentTime = 0
        duration = 0
        availableAudioTracks = []
        selectedAudioTrack = nil
        availableSubtitleTracks = []
        selectedSubtitleTrack = nil
        availableChapters = []
        #if canImport(VLCKit)
        audioTrackByID = [:]
        subtitleTrackByID = [:]
        #endif
        onTracksChanged?()
        onChaptersChanged?()

        #if canImport(VLCKit)
        mediaPlayer.delegate = nil
        mediaPlayer.stop()
        mediaPlayer.delegate = self
        #if canImport(UIKit)
        mediaPlayer.drawable = renderView
        #endif
        guard let media = VLCMedia(url: url) else {
            let message = "Unable to open media URL with VLCKit."
            playbackState = .failed(message)
            onError?(NSError(
                domain: "TVVLCPlayerEngine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            ))
            return
        }
        mediaPlayer.media = media
        playbackState = .loading
        #else
        let message = "VLCKit framework is not linked in this target."
        playbackState = .failed(message)
        onError?(NSError(
            domain: "TVVLCPlayerEngine",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        ))
        #endif
    }

    public func play() {
        #if canImport(VLCKit)
        isExplicitStop = false
        mediaPlayer.play()
        if playbackRate != 1.0 {
            mediaPlayer.rate = playbackRate
        }
        mediaPlayer.audio?.volume = Int32(volumeInternal * 100.0)
        mediaPlayer.audio?.isMuted = isMutedInternal
        if playbackState == .paused || playbackState == .idle {
            playbackState = .playing
        }
        #endif
    }

    public func pause() {
        #if canImport(VLCKit)
        mediaPlayer.pause()
        #endif
        playbackState = .paused
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func seek(to seconds: Double) {
        seek(to: seconds, precision: .automatic)
    }

    public func seek(to seconds: Double, precision: PlayerSeekPrecision) {
        let clamped = duration > 0 ? max(0, min(seconds, duration)) : max(0, seconds)
        currentTime = clamped

        #if canImport(VLCKit)
        guard mediaPlayer.media != nil else { return }
        if mediaPlayer.isSeekable || duration > 0 {
            let targetMs = Int32(clamping: Int64(clamped * 1000.0))
            mediaPlayer.time = VLCTime(int: targetMs)
            pendingSeekSeconds = nil
        } else {
            pendingSeekSeconds = clamped
        }
        #endif
    }

    public func seek(
        to seconds: Double,
        toleranceBefore: Double,
        toleranceAfter: Double,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        let precision: PlayerSeekPrecision
        if toleranceBefore == 0 && toleranceAfter == 0 {
            precision = .exact
        } else if toleranceBefore.isInfinite || toleranceAfter.isInfinite || toleranceBefore >= 5.0 || toleranceAfter >= 5.0 {
            precision = .fast
        } else {
            precision = .automatic
        }
        seek(to: seconds, precision: precision)
        if let completion {
            Task { @MainActor in
                completion(true)
            }
        }
    }

    public func next() {}
    public func previous() {}

    public func selectAudioTrack(_ track: PlayerAudioTrack) {
        selectedAudioTrack = track
        #if canImport(VLCKit)
        if let vlcTrack = audioTrackByID[track.id] {
            vlcTrack.isSelectedExclusively = true
        }
        #endif
        onTracksChanged?()
    }

    public func selectSubtitleTrack(_ track: PlayerSubtitleTrack?) {
        selectedSubtitleTrack = track
        #if canImport(VLCKit)
        if let track, let vlcTrack = subtitleTrackByID[track.id] {
            vlcTrack.isSelectedExclusively = true
        } else {
            mediaPlayer.deselectAllTextTracks()
        }
        #endif
        onTracksChanged?()
    }

    public func tearDown() {
        isExplicitStop = true
        didStartPlayback = false
        didEmitPlaybackEnded = false
        #if canImport(VLCKit)
        mediaPlayer.delegate = nil
        mediaPlayer.stop()
        mediaPlayer.media = nil
        audioTrackByID = [:]
        subtitleTrackByID = [:]
        #endif
        pendingSeekSeconds = nil
        lastKnownAudioTrackCount = -1
        lastKnownSubtitleTrackCount = -1
        lastKnownChapterSignature = ""
        currentTime = 0
        duration = 0
        availableAudioTracks = []
        selectedAudioTrack = nil
        availableSubtitleTracks = []
        selectedSubtitleTrack = nil
        availableChapters = []
        onTracksChanged?()
        onChaptersChanged?()
        playbackState = .idle
    }

    #if canImport(VLCKit)
    private func refreshTracks() {
        let vlcAudioTracks = mediaPlayer.audioTracks
        var nextAudioTracks: [PlayerAudioTrack] = []
        var nextAudioMap: [String: VLCMediaPlayer.Track] = [:]
        var nextSelectedAudio: PlayerAudioTrack?

        for (idx, vlcTrack) in vlcAudioTracks.enumerated() {
            let rawName = vlcTrack.trackName.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawDesc = (vlcTrack.trackDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String
            if !rawName.isEmpty {
                title = rawName
            } else if !rawDesc.isEmpty {
                title = rawDesc
            } else {
                title = "Audio Track \(idx + 1)"
            }
            let trackID = vlcTrack.trackId.isEmpty ? "vlc_audio_\(idx)" : vlcTrack.trackId
            let track = PlayerAudioTrack(id: trackID, title: title, languageCode: vlcTrack.language)
            nextAudioTracks.append(track)
            nextAudioMap[trackID] = vlcTrack
            if vlcTrack.isSelected && nextSelectedAudio == nil {
                nextSelectedAudio = track
            }
        }

        let vlcTextTracks = mediaPlayer.textTracks
        var nextSubtitleTracks: [PlayerSubtitleTrack] = []
        var nextSubtitleMap: [String: VLCMediaPlayer.Track] = [:]
        var nextSelectedSubtitle: PlayerSubtitleTrack?

        for (idx, vlcTrack) in vlcTextTracks.enumerated() {
            let rawName = vlcTrack.trackName.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawDesc = (vlcTrack.trackDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String
            if !rawName.isEmpty {
                title = rawName
            } else if !rawDesc.isEmpty {
                title = rawDesc
            } else {
                title = "Subtitle Track \(idx + 1)"
            }
            let trackID = vlcTrack.trackId.isEmpty ? "vlc_sub_\(idx)" : vlcTrack.trackId
            let track = PlayerSubtitleTrack(id: trackID, title: title, languageCode: vlcTrack.language)
            nextSubtitleTracks.append(track)
            nextSubtitleMap[trackID] = vlcTrack
            if vlcTrack.isSelected && nextSelectedSubtitle == nil {
                nextSelectedSubtitle = track
            }
        }

        lastKnownAudioTrackCount = vlcAudioTracks.count
        lastKnownSubtitleTrackCount = vlcTextTracks.count

        availableAudioTracks = nextAudioTracks
        audioTrackByID = nextAudioMap
        selectedAudioTrack = nextSelectedAudio

        availableSubtitleTracks = nextSubtitleTracks
        subtitleTrackByID = nextSubtitleMap
        selectedSubtitleTrack = nextSelectedSubtitle

        onTracksChanged?()
    }

    private func refreshChaptersIfNeeded() {
        let titleCount = mediaPlayer.numberOfTitles
        guard titleCount > 0 else {
            if !availableChapters.isEmpty {
                lastKnownChapterSignature = ""
                availableChapters = []
                onChaptersChanged?()
            }
            return
        }

        let rawTitleIndex = mediaPlayer.currentTitleIndex
        let resolvedTitleIndex: Int32 = rawTitleIndex >= 0 ? rawTitleIndex : 0
        let chapterCount = mediaPlayer.numberOfChapters(forTitle: resolvedTitleIndex)
        let signature = "\(resolvedTitleIndex):\(chapterCount)"
        guard signature != lastKnownChapterSignature else { return }
        lastKnownChapterSignature = signature

        guard chapterCount > 0 else {
            if !availableChapters.isEmpty {
                availableChapters = []
                onChaptersChanged?()
            }
            return
        }

        let descriptions = mediaPlayer.chapterDescriptions(ofTitle: resolvedTitleIndex)
        guard !descriptions.isEmpty else {
            if !availableChapters.isEmpty {
                availableChapters = []
                onChaptersChanged?()
            }
            return
        }

        var nextChapters: [PlayerChapter] = []
        nextChapters.reserveCapacity(descriptions.count)
        for (idx, desc) in descriptions.enumerated() {
            let startSec = max(0, Double(desc.timeOffset.intValue) / 1000.0)
            let durSec = max(0, Double(desc.durationTime.intValue) / 1000.0)
            let trimmed = (desc.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmed.isEmpty ? "Chapter \(idx + 1)" : trimmed
            nextChapters.append(
                PlayerChapter(
                    id: "vlc_ch_\(desc.titleIndex)_\(desc.chapterIndex)_\(idx)",
                    title: title,
                    startTime: startSec,
                    duration: durSec
                )
            )
        }

        availableChapters = nextChapters.sorted { $0.startTime < $1.startTime }
        onChaptersChanged?()
    }
    #endif
}

#if canImport(VLCKit)
extension TVVLCPlayerEngine: VLCMediaPlayerDelegate {
    public nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, self.mediaPlayer.media != nil else { return }

            let ms = Double(self.mediaPlayer.time.intValue)
            let seconds = ms / 1000.0
            if seconds.isFinite && !seconds.isNaN && seconds >= 0 {
                self.currentTime = seconds
            }

            if let media = self.mediaPlayer.media {
                let lenMs = Double(media.length.intValue)
                let lenSeconds = lenMs / 1000.0
                if lenSeconds.isFinite && !lenSeconds.isNaN && lenSeconds > 0 {
                    self.duration = lenSeconds
                }
            }

            if let pending = self.pendingSeekSeconds, self.mediaPlayer.isSeekable || self.duration > 0 {
                self.pendingSeekSeconds = nil
                self.seek(to: pending)
            }

            if self.mediaPlayer.isPlaying && self.playbackState != .playing {
                self.didStartPlayback = true
                self.playbackState = .playing
            }

            let audioCount = self.mediaPlayer.audioTracks.count
            let subCount = self.mediaPlayer.textTracks.count
            if audioCount != self.lastKnownAudioTrackCount || subCount != self.lastKnownSubtitleTrackCount {
                self.refreshTracks()
            }
            self.refreshChaptersIfNeeded()
        }
    }

    public nonisolated func mediaPlayerLengthChanged(_ length: Int64) {
        Task { @MainActor [weak self] in
            guard let self, self.mediaPlayer.media != nil else { return }
            let lenSeconds = Double(length) / 1000.0
            if lenSeconds.isFinite && !lenSeconds.isNaN && lenSeconds > 0 {
                self.duration = lenSeconds
            }
        }
    }

    public nonisolated func mediaPlayerBufferingChanged(_ progress: Float) {
        Task { @MainActor [weak self] in
            guard let self, self.mediaPlayer.media != nil, !self.isExplicitStop, !self.hasReportedTerminalFailure else { return }
            if progress < 1.0 {
                if self.playbackState != .paused && !self.mediaPlayer.isPlaying {
                    self.playbackState = .buffering
                }
            } else if self.mediaPlayer.isPlaying {
                self.didStartPlayback = true
                self.playbackState = .playing
            }
        }
    }

    public nonisolated func mediaPlayerTrackAdded(_ trackId: String, with type: VLCMedia.TrackType) {
        Task { @MainActor [weak self] in
            guard let self, self.mediaPlayer.media != nil else { return }
            self.refreshTracks()
        }
    }

    public nonisolated func mediaPlayerTrackRemoved(_ trackId: String, with type: VLCMedia.TrackType) {
        Task { @MainActor [weak self] in
            guard let self, self.mediaPlayer.media != nil else { return }
            self.refreshTracks()
        }
    }

    public nonisolated func mediaPlayerTrackUpdated(_ trackId: String, with type: VLCMedia.TrackType) {
        Task { @MainActor [weak self] in
            guard let self, self.mediaPlayer.media != nil else { return }
            self.refreshTracks()
        }
    }

    public nonisolated func mediaPlayerTrackSelected(
        _ trackType: VLCMedia.TrackType,
        selectedId: String,
        unselectedId: String
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.mediaPlayer.media != nil else { return }
            self.refreshTracks()
        }
    }

    public nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        Task { @MainActor [weak self] in
            guard let self, self.mediaPlayer.media != nil else { return }

            switch newState {
            case .playing:
                self.didStartPlayback = true
                self.didEmitPlaybackEnded = false
                self.playbackState = .playing
                if self.playbackRate != 1.0 {
                    self.mediaPlayer.rate = self.playbackRate
                }
                if let audio = self.mediaPlayer.audio {
                    let targetVol = Int32(self.volumeInternal * 100.0)
                    if audio.volume != targetVol {
                        audio.volume = targetVol
                    }
                    if audio.isMuted != self.isMutedInternal {
                        audio.isMuted = self.isMutedInternal
                    }
                }
                if let media = self.mediaPlayer.media {
                    let lenSeconds = Double(media.length.intValue) / 1000.0
                    if lenSeconds.isFinite && !lenSeconds.isNaN && lenSeconds > 0 {
                        self.duration = lenSeconds
                    }
                }
                if let pending = self.pendingSeekSeconds, self.mediaPlayer.isSeekable || self.duration > 0 {
                    self.pendingSeekSeconds = nil
                    self.seek(to: pending)
                }
                self.refreshChaptersIfNeeded()
            case .paused:
                self.playbackState = .paused
            case .opening:
                if self.mediaPlayer.isPlaying {
                    self.didStartPlayback = true
                    self.playbackState = .playing
                } else if self.playbackState != .paused {
                    self.playbackState = .buffering
                }
            case .error:
                guard !self.hasReportedTerminalFailure else { return }
                self.hasReportedTerminalFailure = true
                self.didStartPlayback = false
                let message = "VLC playback error."
                self.playbackState = .failed(message)
                self.onError?(NSError(
                    domain: "TVVLCPlayerEngine",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: message]
                ))
            case .stopped:
                if case .failed = self.playbackState {
                    return
                }
                if self.didStartPlayback && !self.isExplicitStop && !self.hasReportedTerminalFailure && !self.didEmitPlaybackEnded {
                    self.didEmitPlaybackEnded = true
                    self.didStartPlayback = false
                    self.playbackState = .paused
                    self.onPlaybackEnded?()
                } else if self.playbackState != .loading {
                    self.playbackState = .paused
                }
            case .stopping, .nothingSpecial:
                break
            @unknown default:
                if self.mediaPlayer.isPlaying {
                    self.didStartPlayback = true
                    self.playbackState = .playing
                }
            }
        }
    }
}
#endif
