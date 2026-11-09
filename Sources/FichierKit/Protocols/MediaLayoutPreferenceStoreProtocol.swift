//
//  MediaLayoutPreferenceStoreProtocol.swift
//  FichierKit
//
//

import Foundation

/// Abstraction for storing and restoring per-source user layout preferences (grid vs. list).
public protocol MediaLayoutPreferenceStoreProtocol: Sendable {
    /// Saves the selected visual layout for a given source identifier.
    func saveLayout(_ layout: MediaSourceLayout, for sourceID: String) async

    /// Retrieves the saved layout preference for a given source identifier, if any.
    func layout(for sourceID: String) async -> MediaSourceLayout?
}
