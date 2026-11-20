//
//  VideoPlaybackStore.swift
//  FichierKit
//

import Foundation
import Observation
import os

/// Persistent store tracking playback offsets, completion states, and resume positions for video media items.
///
/// ### Architecture & Performance Optimizations
/// - **Actor Isolation**: `@Observable @MainActor public final class`, synchronizing UI updates with run loop.
/// - **Observation Throttling (`@ObservationIgnored`)**: During active video playback, time ticks occur at ~10Hz.
///   Mutating an observed property at that frequency would trigger continuous SwiftUI view re-evaluations.
///   Instead, ticks update `liveRecords`, and only touch `records` when the badge crosses a 5% step (`bucket(of:)`).
/// - **Debounced Disk Persistence**: Avoids constant I/O by debouncing `UserDefaults` saves using a 5-second timer.
@Observable
@MainActor
public final class VideoPlaybackStore: VideoPlaybackStoreProtocol {

    /// Global shared singleton instance.
    public static let shared = VideoPlaybackStore()
    private static let logger = Logger(subsystem: "com.acme.ios.fichierkit", category: "videoPlaybackStore")

    /// Observed playback records dictionary powering UI progress bars and status badges in SwiftUI views.
    public private(set) var records: [String: VideoPlaybackRecord] = [:]

    /// High-frequency unobserved playback position registry updated on every player tick without view invalidations.
    @ObservationIgnored private var liveRecords: [String: VideoPlaybackRecord] = [:]

    /// Debounced asynchronous task handle scheduling writes to persistent storage.
    @ObservationIgnored private var persistTask: Task<Void, Never>?

    /// Storage key in `UserDefaults` storing v2 encoded records.
    private let storageKey = "SMBVideoPlaybackRecords_v2"

    /// Legacy storage key used for one-time v1 position migration.
    private let legacyKey = "SMBVideoPlaybackPositions_v1"

    /// Legacy storage key used for tvOS v1 positions.
    private let tvLegacyKey = "FichierTV_VideoResumePositions_v1"

    /// User defaults database instance backing storage.
    private let userDefaults: UserDefaults

    // MARK: - Initialization & Migration

    /// Initializes the store and performs startup data sanitation and legacy v1 migration.
    ///
    /// - Parameter userDefaults: Target `UserDefaults` suite for persistence. Defaults to `.standard`.
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadRecordsFromStorage()
    }

    private func loadRecordsFromStorage() {
        if let data = userDefaults.data(forKey: storageKey) {
            do {
                let decoded = try JSONDecoder().decode([String: VideoPlaybackRecord].self, from: data)
                self.records = sanitizeDecodedRecords(decoded)
                for (id, record) in self.records where record.duration > 0 {
                    MediaDetailStore.shared.registerDetail(MediaFormatHelper.formatDuration(record.duration), for: id)
                }
                persist()
            } catch {
                Self.logger.error("Failed to decode video playback records from storage: \(error.localizedDescription)")
            }
        } else if let legacyData = userDefaults.data(forKey: legacyKey) {
            do {
                let legacyPositions = try JSONDecoder().decode([String: Double].self, from: legacyData)
                self.records = migrateLegacyV1Positions(legacyPositions)
                persist()
            } catch {
                Self.logger.error("Failed to decode legacy video playback records: \(error.localizedDescription)")
            }
        }

        migrateTVLegacyPositions()
    }

    private func sanitizeDecodedRecords(
        _ decoded: [String: VideoPlaybackRecord]
    ) -> [String: VideoPlaybackRecord] {
        decoded.compactMapValues { record in
            var rec = record
            if rec.duration > 0 && (rec.position >= rec.duration - 4.0 || rec.progress >= 0.90) {
                rec.isFinished = true
            }
            if rec.isFinished {
                if rec.duration >= 2.0 || rec.position >= 2.0 {
                    return rec
                }
            } else if rec.position >= 2.0 {
                return rec
            }
            return nil
        }
    }

    private func migrateLegacyV1Positions(_ legacy: [String: Double]) -> [String: VideoPlaybackRecord] {
        legacy.compactMapValues { pos in
            guard pos >= 3.0 else { return nil }
            return VideoPlaybackRecord(position: pos, duration: 0, isFinished: false)
        }
    }

    private func migrateTVLegacyPositions() {
        guard let tvPositions = userDefaults.dictionary(forKey: tvLegacyKey) as? [String: Double] else { return }
        var hadNewRecords = false
        for (id, pos) in tvPositions where pos >= 3.0 && self.records[id] == nil {
            self.records[id] = VideoPlaybackRecord(position: pos, duration: 0, isFinished: false)
            hadNewRecords = true
        }
        if hadNewRecords {
            persist()
        }
    }

    // MARK: - Status & Position Lookups

    /// Evaluates the discrete playback status badge for an item identifier.
    ///
    /// - Parameters:
    ///   - id: Unique identifier of the media item.
    ///   - fallbackKey: Optional fallback identifier (e.g. SMB path).
    /// - Returns: `.finished`, `.inProgress(progress:)`, or `.unwatched`.
    public func status(for id: String, fallbackKey: String? = nil) -> VideoPlaybackStatus {
        let record = records[id] ?? (fallbackKey.flatMap { records[$0] })
        guard let record else { return .unwatched }
        if record.isFinished {
            return .finished
        }
        if record.duration > 0 && (record.position >= record.duration - 4.0 || record.progress >= 0.90) {
            return .finished
        }
        if record.position >= 3.0 {
            return .inProgress(progress: record.progress)
        }
        return .unwatched
    }

    /// Retrieves the saved resume offset for a video if playback was interrupted mid-stream.
    ///
    /// - Parameters:
    ///   - id: Unique identifier of the media item.
    ///   - fallbackKey: Optional fallback identifier (e.g. SMB path).
    /// - Returns: The resume timestamp in seconds, or `nil` if playback should start from the beginning.
    public func position(for id: String, fallbackKey: String? = nil) -> Double? {
        guard let record = latestRecord(for: id, fallbackKey: fallbackKey),
              !record.isFinished,
              record.position > 3.0 else { return nil }
        if record.duration > 0 {
            if record.position >= record.duration - 4.0 || record.position / record.duration >= 0.90 {
                return nil
            }
        }
        return record.position
    }

    // MARK: - Playback Updates

    /// Records an updated playback progress timestamp from an active video player instance.
    ///
    /// - Parameters:
    ///   - seconds: Current playback head in seconds.
    ///   - duration: Total duration in seconds.
    ///   - id: Target media identifier.
    ///   - fallbackKey: Optional legacy fallback identifier to clean up.
    public func savePosition(_ seconds: Double, duration: Double, for id: String, fallbackKey: String? = nil) {
        guard seconds.isFinite && !seconds.isNaN && duration.isFinite && !duration.isNaN else { return }
        guard seconds >= 2.0 else { return }

        let isNearEnd = duration > 15.0 ? (seconds >= duration - 4.0) : (duration > 0 && seconds >= duration - 1.5)
        let isHighPercentage = duration > 0 ? (seconds / duration >= 0.90) : false

        if duration > 0 {
            MediaDetailStore.shared.registerDetail(MediaFormatHelper.formatDuration(duration), for: id)
        }

        if duration > 0 && (isNearEnd || isHighPercentage) {
            markFinished(for: id, fallbackKey: fallbackKey, duration: duration)
        } else if seconds >= 3.0 {
            let updated = VideoPlaybackRecord(position: seconds, duration: duration, isFinished: false)

            if let fallbackKey {
                records.removeValue(forKey: fallbackKey)
                liveRecords.removeValue(forKey: fallbackKey)
            }

            liveRecords[id] = updated

            if Self.bucket(of: records[id]) != Self.bucket(of: updated) {
                records[id] = updated
            }
            schedulePersist()
        }
    }

    /// Marks a video as completely watched and immediately flushes updates to disk.
    ///
    /// - Parameters:
    ///   - id: Target media identifier.
    ///   - fallbackKey: Optional legacy fallback identifier to clean up.
    ///   - duration: Optional explicit duration override.
    public func markFinished(for id: String, fallbackKey: String? = nil, duration: Double = 0) {
        let existing = latestRecord(for: id, fallbackKey: fallbackKey)
        let dur = duration > 0 ? duration : (existing?.duration ?? 0)
        guard dur >= 2.0 else { return }
        let pos = max(dur, existing?.position ?? 0)

        if let fallbackKey {
            records.removeValue(forKey: fallbackKey)
            liveRecords.removeValue(forKey: fallbackKey)
        }
        liveRecords.removeValue(forKey: id)
        records[id] = VideoPlaybackRecord(position: pos, duration: max(dur, pos), isFinished: true)
        flush()
    }

    /// Clears any recorded progress or completion status for a video.
    ///
    /// - Parameters:
    ///   - id: Target media identifier.
    ///   - fallbackKey: Optional fallback identifier to clean up.
    public func clearPosition(for id: String, fallbackKey: String? = nil) {
        var changed = false
        if liveRecords.removeValue(forKey: id) != nil { changed = true }
        if records.removeValue(forKey: id) != nil { changed = true }
        if let fallbackKey {
            if liveRecords.removeValue(forKey: fallbackKey) != nil { changed = true }
            if records.removeValue(forKey: fallbackKey) != nil { changed = true }
        }
        if changed {
            flush()
        }
    }

    /// Migrates saved video playback progress when a video is renamed.
    ///
    /// - Parameters:
    ///   - oldID: Original media item identifier.
    ///   - newID: New media item identifier.
    public func migratePosition(from oldID: String, to newID: String) {
        if let rec = latestRecord(for: oldID) {
            records[newID] = rec
            clearPosition(for: oldID)
        }
    }

    /// Merges unobserved in-memory positions into the observed dictionary and immediately flushes all records to disk.
    public func flush() {
        persistTask?.cancel()
        persistTask = nil
        if !liveRecords.isEmpty {
            records.merge(liveRecords) { _, live in live }
            liveRecords.removeAll()
        }
        persist()
    }

    // MARK: - VideoPlaybackStoreProtocol Conformance

    /// Persists playback progress for a given media item identifier asynchronously.
    public func savePlaybackPosition(itemID: String, time: Double, duration: Double) async {
        savePosition(time, duration: duration, for: itemID)
    }

    /// Retrieves the saved resume position for a given media item identifier asynchronously.
    public func playbackPosition(for itemID: String) async -> Double? {
        position(for: itemID)
    }

    /// Manually clears saved progress for a given media item identifier asynchronously.
    public func clearPlaybackPosition(for itemID: String) async {
        clearPosition(for: itemID)
    }

    // MARK: - Private Helpers

    private func latestRecord(for id: String, fallbackKey: String? = nil) -> VideoPlaybackRecord? {
        if let live = liveRecords[id] { return live }
        if let rec = records[id] { return rec }
        if let fallbackKey {
            return liveRecords[fallbackKey] ?? records[fallbackKey]
        }
        return nil
    }

    private static func bucket(of record: VideoPlaybackRecord?) -> Int {
        guard let record else { return -1 }
        return record.isFinished ? 100 : Int(record.progress * 20)
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func persist() {
        do {
            let encoded = try JSONEncoder().encode(records)
            userDefaults.set(encoded, forKey: storageKey)
        } catch {
            Self.logger.error("Failed to encode video playback records: \(error.localizedDescription)")
        }
    }
}
