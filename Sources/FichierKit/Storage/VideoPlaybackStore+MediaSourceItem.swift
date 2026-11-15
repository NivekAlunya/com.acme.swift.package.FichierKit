//
//  VideoPlaybackStore+MediaSourceItem.swift
//  FichierKit
//

import Foundation

extension VideoPlaybackStore {
    private func fallbackKey(for item: MediaSourceItem) -> String? {
        guard let share = item.smbShare, let path = item.smbPath else { return nil }
        return "\(share)::\(path)"
    }

    /// Evaluates the discrete playback status badge for a `MediaSourceItem`.
    public func status(for item: MediaSourceItem) -> VideoPlaybackStatus {
        status(for: item.id, fallbackKey: fallbackKey(for: item))
    }

    /// Retrieves the saved resume offset for a `MediaSourceItem`.
    public func position(for item: MediaSourceItem) -> Double? {
        position(for: item.id, fallbackKey: fallbackKey(for: item))
    }

    /// Records an updated playback progress timestamp for a `MediaSourceItem`.
    public func savePosition(_ seconds: Double, duration: Double, for item: MediaSourceItem) {
        savePosition(seconds, duration: duration, for: item.id, fallbackKey: fallbackKey(for: item))
    }

    /// Marks a `MediaSourceItem` as completely watched and immediately flushes updates to disk.
    public func markFinished(for item: MediaSourceItem, duration: Double = 0) {
        markFinished(for: item.id, fallbackKey: fallbackKey(for: item), duration: duration)
    }

    /// Clears any recorded progress or completion status for a `MediaSourceItem`.
    public func clearPosition(for item: MediaSourceItem) {
        clearPosition(for: item.id, fallbackKey: fallbackKey(for: item))
    }
}
