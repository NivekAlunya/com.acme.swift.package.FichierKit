//
//  DefaultMediaLayoutPreferenceStore.swift
//  FichierKit
//
//

import Foundation

/// Actor-isolated `UserDefaults` store remembering the last chosen browser layout per media source.
public actor DefaultMediaLayoutPreferenceStore: MediaLayoutPreferenceStoreProtocol {
    public static let shared = DefaultMediaLayoutPreferenceStore()

    private let userDefaults: UserDefaults
    private let keyPrefix = "FichierTV_LayoutPreference_v1_"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func saveLayout(_ layout: MediaSourceLayout, for sourceID: String) async {
        userDefaults.set(layout.rawValue, forKey: keyPrefix + sourceID)
    }

    public func layout(for sourceID: String) async -> MediaSourceLayout? {
        guard let rawValue = userDefaults.string(forKey: keyPrefix + sourceID) else {
            return nil
        }
        return MediaSourceLayout(rawValue: rawValue)
    }
}
