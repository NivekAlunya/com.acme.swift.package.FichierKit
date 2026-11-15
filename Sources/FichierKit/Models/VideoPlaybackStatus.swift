//
//  VideoPlaybackStatus.swift
//  FichierKit
//

import Foundation

/// Discrete playback progress state indicating the completion tier of a video asset.
///
/// Used by gallery cells to render progress rings and badges (e.g. unwatched, in-progress, or finished).
public enum VideoPlaybackStatus: Sendable, Equatable {
    /// The video has not been started or has less than 2% watched progress.
    case unwatched

    /// The video has been partially watched.
    ///
    /// - Parameter progress: Normalized completion percentage clamped between 0.0 and 1.0.
    case inProgress(progress: Double)

    /// The video playback reached completion (typically exceeding 95% total runtime).
    case finished
}
