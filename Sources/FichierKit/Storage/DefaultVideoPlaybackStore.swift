//
//  DefaultVideoPlaybackStore.swift
//  FichierKit
//

import Foundation

/// Actor-isolated store persisting video resume timestamps in `UserDefaults`.
public actor DefaultVideoPlaybackStore: VideoPlaybackStoreProtocol {
    public static let shared = DefaultVideoPlaybackStore()

    private let userDefaults: UserDefaults
    private let storageKey = "FichierTV_VideoResumePositions_v1"
    private let minResumeThreshold: Double = 10.0
    private let endCompletionMargin: Double = 15.0

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func savePlaybackPosition(itemID: String, time: Double, duration: Double) async {
        var positions = loadDictionary()

        // If completed or near completion, clear position
        if duration > 0 && time >= (duration - endCompletionMargin) {
            positions.removeValue(forKey: itemID)
        } else if time >= minResumeThreshold {
            positions[itemID] = time
        } else {
            positions.removeValue(forKey: itemID)
        }

        saveDictionary(positions)
    }

    public func playbackPosition(for itemID: String) async -> Double? {
        let positions = loadDictionary()
        guard let position = positions[itemID], position >= minResumeThreshold else {
            return nil
        }
        return position
    }

    public func clearPlaybackPosition(for itemID: String) async {
        var positions = loadDictionary()
        positions.removeValue(forKey: itemID)
        saveDictionary(positions)
    }

    private func loadDictionary() -> [String: Double] {
        userDefaults.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
    }

    private func saveDictionary(_ dict: [String: Double]) {
        userDefaults.set(dict, forKey: storageKey)
    }
}
