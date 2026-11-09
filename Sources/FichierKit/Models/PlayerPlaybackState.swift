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
}
