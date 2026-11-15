//
//  SlideshowTransitionStyle.swift
//  FichierKit
//

import Foundation

/// Animation style applied when transitioning between photos in slideshow mode.
public enum SlideshowTransitionStyle: String, Sendable, CaseIterable, Identifiable {
    case fade = "Fade"
    case slide = "Slide"
    case kenBurns = "Ken Burns"

    public var id: String { rawValue }
}
