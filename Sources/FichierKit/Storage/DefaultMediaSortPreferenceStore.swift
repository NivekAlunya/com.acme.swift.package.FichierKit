//
//  DefaultMediaSortPreferenceStore.swift
//  FichierKit
//

import Foundation

/// Actor-isolated `UserDefaults` store remembering the last chosen sort configuration per media source.
public actor DefaultMediaSortPreferenceStore: MediaSortPreferenceStoreProtocol {
    public static let shared = DefaultMediaSortPreferenceStore()

    private let userDefaults: UserDefaults
    private let keyPrefix = "FichierTV_SortPreference_v1_"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func savePreference(_ preference: MediaSortPreference, for sourceID: String) async {
        guard let encoded = try? JSONEncoder().encode(preference) else { return }
        userDefaults.set(encoded, forKey: keyPrefix + sourceID)
    }

    public func preference(for sourceID: String) async -> MediaSortPreference? {
        guard let data = userDefaults.data(forKey: keyPrefix + sourceID) else {
            return nil
        }
        return try? JSONDecoder().decode(MediaSortPreference.self, from: data)
    }
}
