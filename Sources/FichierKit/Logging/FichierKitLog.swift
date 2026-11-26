//
//  FichierKitLog.swift
//  FichierKit
//

import os

/// Centralized privacy-safe `os.Logger` categories for `FichierKit`.
enum FichierKitLog {
    private static let subsystem = "com.acme.ios.fichierkit"

    static let savedSMBConnection = Logger(subsystem: subsystem, category: "savedSMBConnection")
    static let videoPlaybackStore = Logger(subsystem: subsystem, category: "videoPlaybackStore")
    static let imageLoader = Logger(subsystem: subsystem, category: "imageLoader")
    static let favoritesManager = Logger(subsystem: subsystem, category: "favoritesManager")
    static let sortPreferenceStore = Logger(subsystem: subsystem, category: "sortPreferenceStore")
    static let discovery = Logger(subsystem: subsystem, category: "discovery")
}
