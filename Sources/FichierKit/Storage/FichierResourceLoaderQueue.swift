//
//  FichierResourceLoaderQueue.swift
//  FichierKit
//

import Foundation

/// Centralized `DispatchQueue` shared by `AVAssetResourceLoader` delegates across iOS, tvOS, and `FichierKit`.
public enum FichierResourceLoaderQueue: Sendable {
    // AVAssetResourceLoader.setDelegate(_:queue:) requires a DispatchQueue; no async API exists.
    // swiftlint:disable:next no_legacy_dispatch_queue
    public static let shared = DispatchQueue(
        label: "com.fichierkit.resourceloader",
        qos: .userInitiated
    )
}
