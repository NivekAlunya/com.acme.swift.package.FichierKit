//
//  VideoPlayerErrorSanitizer.swift
//  FichierKit
//

import Foundation

/// Redacts sensitive IP addresses and SMB credentials from player error strings before UI presentation.
public enum VideoPlayerErrorSanitizer: Sendable {
    public static func sanitize(_ rawDescription: String) -> String {
        // Redact IPv4 addresses (e.g. 192.168.1.100)
        var sanitized = rawDescription.replacingOccurrences(
            of: #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#,
            with: "<host>",
            options: .regularExpression
        )
        // Redact SMB URLs/credentials (e.g. smb://user:pass@host/share)
        sanitized = sanitized.replacingOccurrences(
            of: #"smb://[^\s/]+"#,
            with: "smb://<server>",
            options: .regularExpression
        )
        return sanitized
    }
}
