//
//  AVPlayerEngine.swift
//  FichierKit
//
//

import Foundation
import AVFoundation

/// AVFoundation playback engine conforming to `PlayerEngine`.
///
/// Drives hardware-accelerated playback for native formats (`.mp4`, `.mov`, `.m4v`),
/// managing periodic time updates, media selection tracks, and precision scrubbing.
@MainActor
public final class AVPlayerEngine: NSObject, PlayerEngine {
    public let avPlayer: AVPlayer

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
        avPlayer.timeControlStatus == .playing || (avPlayer.rate > 0 && avPlayer.error == nil)
    }

    public var onPlaybackEnded: (@MainActor @Sendable () -> Void)?
    public var onError: (@MainActor @Sendable (Error) -> Void)?
    public var onStateUpdate: (@MainActor @Sendable (PlayerPlaybackState) -> Void)?
    public var onTimeUpdate: (@MainActor @Sendable (Double) -> Void)?
    public var onDurationUpdate: (@MainActor @Sendable (Double) -> Void)?
    public var onTracksChanged: (@MainActor @Sendable () -> Void)?
    public var onChaptersChanged: (@MainActor @Sendable () -> Void)?

    private var timeObserverToken: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var audibleGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?
    private var trackLoadingTask: Task<Void, Never>?

    public init(player: AVPlayer = AVPlayer()) {
        self.avPlayer = player
        super.init()
        setupObservers()
    }

    /// Loads a media URL for playback.
    public func load(url: URL) {
        tearDownCurrentItem()
        currentTime = 0
        duration = 0
        availableAudioTracks = []
        selectedAudioTrack = nil
        availableSubtitleTracks = []
        selectedSubtitleTrack = nil
        availableChapters = []
        onTracksChanged?()
        onChaptersChanged?()

        let playerItem = AVPlayerItem(url: url)
        observePlayerItem(playerItem)
        avPlayer.replaceCurrentItem(with: playerItem)
        playbackState = .loading
    }

    public func play() {
        avPlayer.play()
        playbackState = .playing
    }

    public func pause() {
        avPlayer.pause()
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
        let previousTime = currentTime
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        currentTime = clamped
        let targetTime = CMTime(seconds: clamped, preferredTimescale: 600)
        let tolerance = Self.resolvedTolerance(
            deltaSeconds: abs(clamped - previousTime),
            precision: precision
        )
        avPlayer.currentItem?.cancelPendingSeeks()
        avPlayer.seek(to: targetTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    public func next() {}
    public func previous() {}

    public func selectAudioTrack(_ track: PlayerAudioTrack) {
        guard let item = avPlayer.currentItem, let group = audibleGroup else { return }
        if let option = group.options.first(where: { $0.displayName == track.title }) {
            item.select(option, in: group)
            selectedAudioTrack = track
            onTracksChanged?()
        }
    }

    public func selectSubtitleTrack(_ track: PlayerSubtitleTrack?) {
        guard let item = avPlayer.currentItem, let group = legibleGroup else { return }
        if let track, let option = group.options.first(where: { $0.displayName == track.title }) {
            item.select(option, in: group)
            selectedSubtitleTrack = track
        } else {
            item.select(nil, in: group)
            selectedSubtitleTrack = nil
        }
        onTracksChanged?()
    }

    public func tearDown() {
        if let timeObserverToken {
            avPlayer.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        tearDownCurrentItem()
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
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

    // MARK: - Private Observers

    private func setupObservers() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let sec = time.seconds
                if sec.isFinite && !sec.isNaN {
                    self.currentTime = max(0, sec)
                }
            }
        }

        timeControlObserver = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, player.currentItem != nil else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.playbackState = .playing
                case .paused:
                    if case .failed = self.playbackState {
                        return
                    }
                    self.playbackState = .paused
                case .waitingToPlayAtSpecifiedRate:
                    self.playbackState = .buffering
                @unknown default:
                    break
                }
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] playerItem, _ in
            Task { @MainActor [weak self] in
                guard let self, self.avPlayer.currentItem === playerItem else { return }
                switch playerItem.status {
                case .readyToPlay:
                    let d = playerItem.duration.seconds
                    self.duration = (d.isFinite && !d.isNaN && d > 0) ? d : 0
                    self.trackLoadingTask?.cancel()
                    self.trackLoadingTask = Task {
                        await self.populateTracksAsync(for: playerItem)
                    }
                    self.playbackState = self.isPlaying ? .playing : .paused
                case .failed:
                    let message = playerItem.error?.localizedDescription ?? "Playback failed."
                    self.playbackState = .failed(message)
                    if let error = playerItem.error {
                        self.onError?(error)
                    } else {
                        self.onError?(NSError(
                            domain: "AVPlayerEngine",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: message]
                        ))
                    }
                case .unknown:
                    self.playbackState = .loading
                @unknown default:
                    break
                }
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemDidPlayToEndTime),
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )
    }

    private func populateTracksAsync(for item: AVPlayerItem) async {
        do {
            let audible = try await item.asset.loadMediaSelectionGroup(for: .audible)
            guard !Task.isCancelled, avPlayer.currentItem === item else { return }
            self.audibleGroup = audible
            if let audible {
                self.availableAudioTracks = audible.options.enumerated().map { index, option in
                    PlayerAudioTrack(
                        id: "audio_\(index)",
                        title: option.displayName,
                        languageCode: option.extendedLanguageTag
                    )
                }
                if let selected = item.currentMediaSelection.selectedMediaOption(in: audible) {
                    self.selectedAudioTrack = self.availableAudioTracks.first(where: { $0.title == selected.displayName })
                }
            }

            let legible = try await item.asset.loadMediaSelectionGroup(for: .legible)
            guard !Task.isCancelled, avPlayer.currentItem === item else { return }
            self.legibleGroup = legible
            if let legible {
                self.availableSubtitleTracks = legible.options.enumerated().map { index, option in
                    PlayerSubtitleTrack(
                        id: "subtitle_\(index)",
                        title: option.displayName,
                        languageCode: option.extendedLanguageTag
                    )
                }
                if let selected = item.currentMediaSelection.selectedMediaOption(in: legible) {
                    self.selectedSubtitleTrack = self.availableSubtitleTracks.first(where: { $0.title == selected.displayName })
                }
            }
            onTracksChanged?()
        } catch {
            // Asset does not support media selection groups
        }

        await populateChaptersAsync(for: item)
    }

    private func populateChaptersAsync(for item: AVPlayerItem) async {
        do {
            let locales = try await item.asset.load(.availableChapterLocales)
            guard !Task.isCancelled, avPlayer.currentItem === item, !locales.isEmpty else { return }

            var groups = try await item.asset.loadChapterMetadataGroups(
                bestMatchingPreferredLanguages: Locale.preferredLanguages
            )
            if groups.isEmpty, let firstLocale = locales.first {
                groups = try await item.asset.loadChapterMetadataGroups(
                    withTitleLocale: firstLocale,
                    containingItemsWithCommonKeys: []
                )
            }

            var resolvedChapters: [PlayerChapter] = []
            resolvedChapters.reserveCapacity(groups.count)
            for (index, group) in groups.enumerated() {
                if Task.isCancelled || avPlayer.currentItem !== item { return }
                let startSec = max(0, group.timeRange.start.seconds)
                guard startSec.isFinite && !startSec.isNaN else { continue }
                let durSec = max(0, group.timeRange.duration.seconds)
                let safeDur = (durSec.isFinite && !durSec.isNaN) ? durSec : 0

                var rawTitle = ""
                if let titleItem = group.items.first(where: { $0.commonKey == .commonKeyTitle }),
                   let loadedTitle = try? await titleItem.load(.stringValue) {
                    rawTitle = loadedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                let title = rawTitle.isEmpty ? "Chapter \(index + 1)" : rawTitle
                resolvedChapters.append(
                    PlayerChapter(
                        id: "av_ch_\(index)_\(Int(startSec * 1000))",
                        title: title,
                        startTime: startSec,
                        duration: safeDur
                    )
                )
            }

            guard !Task.isCancelled, avPlayer.currentItem === item else { return }
            availableChapters = resolvedChapters.sorted { $0.startTime < $1.startTime }
            onChaptersChanged?()
        } catch {
            // Asset does not carry chapter metadata
        }
    }

    private static func resolvedTolerance(deltaSeconds: Double, precision: PlayerSeekPrecision) -> CMTime {
        switch precision {
        case .exact:
            return .zero
        case .fast:
            return .positiveInfinity
        case .automatic:
            if deltaSeconds >= 5.0 {
                return .positiveInfinity
            }
            if deltaSeconds >= 1.0 {
                return CMTime(seconds: 0.5, preferredTimescale: 600)
            }
            return .zero
        }
    }

    private func tearDownCurrentItem() {
        trackLoadingTask?.cancel()
        trackLoadingTask = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        audibleGroup = nil
        legibleGroup = nil
        NotificationCenter.default.removeObserver(self, name: AVPlayerItem.didPlayToEndTimeNotification, object: nil)
    }

    @objc private func handleItemDidPlayToEndTime() {
        playbackState = .paused
        onPlaybackEnded?()
    }
}
