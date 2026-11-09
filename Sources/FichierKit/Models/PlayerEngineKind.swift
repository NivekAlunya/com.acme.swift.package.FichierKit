//
//  PlayerEngineKind.swift
//  FichierKit
//
//

import Foundation

/// Identifies which underlying playback backend renders the active video stream.
public enum PlayerEngineKind: String, Sendable, Equatable {
    case native
    case extended
}
