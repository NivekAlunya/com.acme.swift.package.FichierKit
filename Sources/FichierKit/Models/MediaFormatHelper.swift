//
//  MediaFormatHelper.swift
//  FichierKit
//

import Foundation

/// Utility helper for formatting bytes and timestamps consistently across platforms.
public enum MediaFormatHelper: Sendable {
    /// Formats a raw byte count into human-readable text (e.g. "14.2 MB").
    public static func formatByteCount(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        return bytes.formatted(.byteCount(style: .file))
    }

    /// Formats an optional date into localized display text.
    public static func formatDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
