//
//  VideoPlaybackStoreProtocol.swift
//  FichierKit
//

import Foundation

/// Abstraction for persisting video playback positions to support resume-playback across sessions.
public protocol VideoPlaybackStoreProtocol: Sendable {
    /// Persists playback progress for a given media item.
    ///
    /// Ignores positions less than 10 seconds in, and clears progress if within 15 seconds of the end.
    func savePlaybackPosition(itemID: String, time: Double, duration: Double) async

    /// Retrieves the saved resume position for a given media item, or `nil` if none or completed.
    func playbackPosition(for itemID: String) async -> Double?

    /// Manually clears saved progress for a given media item.
    func clearPlaybackPosition(for itemID: String) async
}
