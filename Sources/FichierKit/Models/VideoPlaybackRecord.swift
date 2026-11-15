//
//  VideoPlaybackRecord.swift
//  FichierKit
//

import Foundation

/// Persistent record tracking the playback position, total duration, and completion status of a video file.
///
/// Serialized to disk using `JSONEncoder` in `VideoPlaybackStore` to facilitate cross-session resume functionality.
public struct VideoPlaybackRecord: Codable, Sendable, Equatable {
    /// The last recorded playback timestamp in seconds.
    public var position: Double

    /// The total duration of the video asset in seconds.
    public var duration: Double

    /// Flag indicating whether playback reached the end threshold.
    public var isFinished: Bool

    /// Initializes a video playback record.
    ///
    /// - Parameters:
    ///   - position: Playback offset in seconds.
    ///   - duration: Total runtime in seconds.
    ///   - isFinished: Whether the video is considered fully watched. Defaults to `false`.
    public init(position: Double, duration: Double, isFinished: Bool = false) {
        self.position = position
        self.duration = duration
        self.isFinished = isFinished
    }

    /// Normalized playback progress ratio bounded between `0.0` (unstarted) and `1.0` (completed).
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return max(0.0, min(1.0, position / duration))
    }
}
