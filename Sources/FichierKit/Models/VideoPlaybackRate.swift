//
//  VideoPlaybackRate.swift
//  FichierKit
//
//

import Foundation

/// Supported playback rate multipliers for video playback (`AVPlayerEngine` and `VLCPlayerEngine`).
///
/// Provides selectable speeds ranging from half-speed slow motion (`0.5×`) to double-speed (`2.0×`).
public enum VideoPlaybackRate: Float, CaseIterable, Identifiable, Sendable {
    /// Half-speed slow motion playback (0.5×).
    case speed0_5 = 0.5

    /// Three-quarter speed playback (0.75×).
    case speed0_75 = 0.75

    /// Standard real-time playback speed (1.0×).
    case normal = 1.0

    /// 1.25× accelerated playback.
    case speed1_25 = 1.25

    /// 1.5× fast playback.
    case speed1_5 = 1.5

    /// Double-speed rapid playback (2.0×).
    case speed2_0 = 2.0

    /// Identifiable conformance identifier mapped to the raw `Float` multiplier.
    public var id: Float { rawValue }

    /// User-facing display title formatted with multiplication glyph (e.g. "1.5×").
    public var displayName: String {
        switch self {
        case .speed0_5:
            return "0.5×"
        case .speed0_75:
            return "0.75×"
        case .normal:
            return "1.0×"
        case .speed1_25:
            return "1.25×"
        case .speed1_5:
            return "1.5×"
        case .speed2_0:
            return "2.0×"
        }
    }
}
