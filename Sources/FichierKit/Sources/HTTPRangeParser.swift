//
//  HTTPRangeParser.swift
//  FichierKit
//
//

import Foundation

/// Parses HTTP `Range` request headers into validated byte intervals.
public enum HTTPRangeParser: Sendable {
    /// Parses a `Range: bytes=...` header against a known resource size.
    ///
    /// - Parameters:
    ///   - header: Raw HTTP header line (e.g., `"Range: bytes=0-1023"`, `"Range: bytes=1024-"`, `"Range: bytes=-500"`).
    ///   - totalSize: Total byte length of the target resource.
    /// - Returns: Inclusive `(start, end)` byte offsets if satisfiable; `nil` otherwise.
    public static func parse(_ header: String, totalSize: Int64) -> (start: Int64, end: Int64)? {
        guard totalSize > 0 else { return nil }
        guard let eqIndex = header.firstIndex(of: "=") else { return nil }

        let prefix = header[..<eqIndex].trimmingCharacters(in: .whitespaces).lowercased()
        guard prefix == "range: bytes" || prefix == "bytes" else { return nil }

        let spec = header[header.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
        guard !spec.contains(",") else { return nil }

        let bounds = spec.components(separatedBy: "-")
        guard bounds.count == 2 else { return nil }

        let startStr = bounds[0].trimmingCharacters(in: .whitespaces)
        let endStr = bounds[1].trimmingCharacters(in: .whitespaces)

        if startStr.isEmpty {
            guard let suffixLength = Int64(endStr), suffixLength > 0 else { return nil }
            let start = max(0, totalSize - suffixLength)
            let end = totalSize - 1
            return (start, end)
        } else if endStr.isEmpty {
            guard let start = Int64(startStr), start >= 0, start < totalSize else { return nil }
            let end = totalSize - 1
            return (start, end)
        } else {
            guard let start = Int64(startStr), let endVal = Int64(endStr) else { return nil }
            guard start >= 0, start < totalSize, endVal >= start else { return nil }
            let end = min(endVal, totalSize - 1)
            return (start, end)
        }
    }
}
