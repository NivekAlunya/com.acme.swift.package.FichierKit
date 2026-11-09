//
//  DefaultSlideshowSettingsStore.swift
//  FichierKit
//

import Foundation

/// Actor-isolated `UserDefaults` store managing slideshow interval and transition style.
public actor DefaultSlideshowSettingsStore: SlideshowSettingsStoreProtocol {
    public static let shared = DefaultSlideshowSettingsStore()

    private let userDefaults: UserDefaults
    private let intervalKey = "FichierTV_SlideshowInterval_v1"
    private let styleKey = "FichierTV_SlideshowTransitionStyle_v1"
    private let defaultInterval: TimeInterval = 4.0

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadInterval() async -> TimeInterval {
        let value = userDefaults.double(forKey: intervalKey)
        return value > 0 ? value : defaultInterval
    }

    public func saveInterval(_ interval: TimeInterval) async {
        userDefaults.set(interval, forKey: intervalKey)
    }

    public func loadTransitionStyle() async -> SlideshowTransitionStyle {
        guard let rawValue = userDefaults.string(forKey: styleKey),
              let style = SlideshowTransitionStyle(rawValue: rawValue) else {
            return .slide
        }
        return style
    }

    public func saveTransitionStyle(_ style: SlideshowTransitionStyle) async {
        userDefaults.set(style.rawValue, forKey: styleKey)
    }
}
