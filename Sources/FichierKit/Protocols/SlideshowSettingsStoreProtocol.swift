//
//  SlideshowSettingsStoreProtocol.swift
//  FichierKit
//

import Foundation

/// Abstraction for persisting user slideshow preferences (interval duration and transition style).
public protocol SlideshowSettingsStoreProtocol: Sendable {
    /// Retrieves the persisted slideshow interval duration in seconds (default: 4.0s).
    func loadInterval() async -> TimeInterval

    /// Persists a new slideshow interval duration in seconds.
    func saveInterval(_ interval: TimeInterval) async

    /// Retrieves the persisted transition animation style (default: `.slide`).
    func loadTransitionStyle() async -> SlideshowTransitionStyle

    /// Persists a new transition animation style.
    func saveTransitionStyle(_ style: SlideshowTransitionStyle) async
}
