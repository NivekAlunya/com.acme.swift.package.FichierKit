//
//  MediaSortPreferenceStoreProtocol.swift
//  FichierKit
//

import Foundation

/// Abstraction for storing and restoring per-source user sorting preferences.
public protocol MediaSortPreferenceStoreProtocol: Sendable {
    /// Saves the selected sort key and order for a given source identifier.
    func savePreference(_ preference: MediaSortPreference, for sourceID: String) async

    /// Retrieves the saved sort preference for a given source identifier, if any.
    func preference(for sourceID: String) async -> MediaSortPreference?
}
