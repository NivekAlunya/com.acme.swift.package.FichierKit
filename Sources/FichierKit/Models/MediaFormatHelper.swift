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

    /// Formats a playback duration in seconds into a standard timestamp string (e.g. "02:45" or "1:15:30").
    public static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds > 0 && seconds < Double(Int.max) else { return "" }
        let total = Int(seconds.rounded())
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    /// Formats a playback timestamp in seconds into `MM:SS` or `HH:MM:SS`.
    public static func formatTimestamp(
        _ seconds: Double,
        zeroPaddedHours: Bool = true,
        zeroPaddedMinutes: Bool = true
    ) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds > 0 && seconds < Double(Int.max) else {
            return zeroPaddedMinutes ? "00:00" : "0:00"
        }
        let total = Int(seconds.rounded())
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return zeroPaddedHours ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return zeroPaddedMinutes ? String(format: "%02d:%02d", m, s) : String(format: "%d:%02d", m, s)
        }
    }

    /// Formats image width and height into a dimensions descriptor string (e.g. "3840 × 2160").
    public static func formatDimensions(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else { return "" }
        return "\(width) × \(height)"
    }

    /// Formats a PDF page count into a human-readable label (e.g. "1 page", "12 pages").
    public static func formatPageCount(_ pages: Int) -> String {
        guard pages > 0 else { return "" }
        return pages == 1 ? "1 page" : "\(pages) pages"
    }
}
