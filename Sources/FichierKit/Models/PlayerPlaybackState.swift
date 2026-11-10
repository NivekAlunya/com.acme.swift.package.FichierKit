//
//  PlayerPlaybackState.swift
//  FichierKit
//

import Foundation

/// Discrete operational states for the video playback pipeline.
public enum PlayerPlaybackState: Sendable, Equatable {
    case idle
    case loading
    case buffering
    case playing
    case paused
    case failed(String)

    /// Indicates whether media playback is actively advancing.
    public var isPlaying: Bool {
        self == .playing
    }

    /// Indicates whether the player is waiting on initial load or network buffering.
    public var isBuffering: Bool {
        self == .loading || self == .buffering
    }
}
