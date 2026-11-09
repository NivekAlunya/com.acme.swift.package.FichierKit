//
//  SlideshowTransitionStyle.swift
//  FichierKit
//

import Foundation

/// Animation style applied when transitioning between photos in slideshow mode.
public enum SlideshowTransitionStyle: String, Sendable, CaseIterable, Identifiable {
    case fade = "Fade"
    case slide = "Slide"

    public var id: String { rawValue }
}
