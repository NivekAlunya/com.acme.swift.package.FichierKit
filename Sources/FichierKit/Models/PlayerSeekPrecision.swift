//
//  PlayerSeekPrecision.swift
//  FichierKit
//
//

import Foundation

/// Controls decoder keyframe tolerance strategy when seeking playback.
public enum PlayerSeekPrecision: Equatable, Sendable {
    /// Uses fast nearest-keyframe snapping for multi-second jumps (`>= 5s`) and tight tolerance for short nudges.
    case automatic
    /// Forces frame-accurate zero-tolerance decoding.
    case exact
    /// Snaps directly to the nearest keyframe (`tolerance = .infinity`) for minimal SMB latency.
    case fast
}
