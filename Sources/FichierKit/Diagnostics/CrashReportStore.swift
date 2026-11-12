//
//  CrashReportStore.swift
//  FichierKit
//

import Foundation

/// Persists crash reports as plain-text files so they survive across launches and can be shared from Settings.
///
/// Wappn writes a single `last_crash.json` that is deleted once handled. This store keeps a durable,
/// human-readable archive instead, one file per crash, so a report is still available after later
/// (successful) launches. Only the most recent `maxArchivedReports` files are retained.
///
/// The type is a value type holding only a `URL`, so it is `Sendable` and callable from any actor.
public nonisolated struct CrashReportStore: Sendable {

    /// Directory holding the archived `crash-*.txt` reports.
    public let directoryURL: URL

    /// Maximum number of reports kept on disk; older ones are deleted after each archive.
    public let maxArchivedReports: Int

    private static let filePrefix = "crash-"
    private static let fileExtension = "txt"

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - directoryURL: Folder for archived reports. Defaults to `Application Support/CrashReports`.
    ///   - maxArchivedReports: Retention limit (at least 1).
    public init(directoryURL: URL = CrashReportStore.defaultDirectoryURL, maxArchivedReports: Int = 10) {
        self.directoryURL = directoryURL
        self.maxArchivedReports = max(1, maxArchivedReports)
    }

    /// Default archive location, in Application Support so it is not exposed in the Files app.
    public static var defaultDirectoryURL: URL {
        URL.applicationSupportDirectory.appending(path: "CrashReports", directoryHint: .isDirectory)
    }

    /// Writes `text` to a new timestamped report file and prunes old reports.
    ///
    /// - Parameters:
    ///   - text: Full report contents.
    ///   - date: Date used for the file name (injectable for tests).
    /// - Returns: The URL of the created file.
    @discardableResult
    public func archive(_ text: String, date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let stamp = date.formatted(
            .iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted)
        )
        // Two crashes within the same second must not overwrite each other.
        // Suffixes are formatted with 3-digit zero-padding (_001, _002, ...) so lexicographical
        // descending sorting preserves true chronological order across single and multi-digit collision numbers.
        // POSIX open with O_CREAT | O_EXCL eliminates TOCTOU races when multiple threads archive simultaneously.
        var suffix = 0
        while true {
            let candidateURL: URL
            if suffix == 0 {
                candidateURL = directoryURL.appending(path: "\(Self.filePrefix)\(stamp).\(Self.fileExtension)")
            } else {
                let suffixString = String(format: "%03d", suffix)
                candidateURL = directoryURL.appending(path: "\(Self.filePrefix)\(stamp)_\(suffixString).\(Self.fileExtension)")
            }

            let path = candidateURL.path
            let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            if fd >= 0 {
                // Successfully acquired exclusive file handle
                let data = Array(text.utf8)
                let written = data.withUnsafeBufferPointer { buf in
                    buf.baseAddress.map { write(fd, $0, buf.count) } ?? 0
                }
                close(fd)
                if written < 0 {
                    try? FileManager.default.removeItem(at: candidateURL)
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                pruneOldReports()
                return candidateURL
            } else if errno == EEXIST {
                // Collision; try next sequence suffix
                suffix += 1
            } else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    /// The most recently archived report, or `nil` when none exists.
    public func latestReportURL() -> URL? {
        reportURLsNewestFirst().first
    }

    // MARK: - Private

    /// Archived reports sorted newest first. File names embed a sortable timestamp, so sorting by name
    /// descending is enough and does not depend on file-system dates.
    private func reportURLsNewestFirst() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix(Self.filePrefix) && $0.pathExtension == Self.fileExtension }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func pruneOldReports() {
        for url in reportURLsNewestFirst().dropFirst(maxArchivedReports) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
