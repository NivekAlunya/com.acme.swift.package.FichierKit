//
//  FichierKitLog.swift
//  FichierKit
//

import Foundation

/// Privacy helpers for `FichierKit` diagnostic logging via `Wappn`.
enum FichierKitLog {
    /// Masks sensitive strings (paths, shares, source IDs) in diagnostic messages.
    static func redacted(_ value: String) -> String {
        value.isEmpty ? "<empty>" : "<private>"
    }
}
