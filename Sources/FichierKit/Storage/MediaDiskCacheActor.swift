//
//  MediaDiskCacheActor.swift
//  FichierKit
//

import Foundation
import Wappn

/// Actor isolating all on-disk cache mutations, atomic writes, legacy file migrations, and eviction sweeps.
///
/// ### Architecture & Concurrency
/// - **Actor Isolation**: Guarantees mutually exclusive serial execution for filesystem mutations (writes, moves, removals),
///   preventing data corruption and race conditions between background eviction tasks and active file operations.
/// - **Structured Logging**: Replaces silent error swallowing with structured diagnostics via Wappn `log`.
public actor MediaDiskCacheActor {
    
    /// Global shared disk cache actor.
    public static let shared = MediaDiskCacheActor()
    
    /// Underlying file manager instance used exclusively within this actor.
    private let fileManager = FileManager()
    
    public init() {}
    
    // MARK: - Atomic Writes & Reads

    /// Reads binary data from the specified file URL isolated on the disk actor.
    ///
    /// - Parameter url: The file URL to read.
    /// - Returns: The data contents if the file exists and is readable, or `nil` otherwise.
    public func readData(from url: URL) -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }
    
    /// Atomically writes data to the specified destination URL.
    ///
    /// - Parameters:
    ///   - data: The binary payload to persist.
    ///   - url: The target file destination URL.
    /// - Throws: An error if directory creation or file writing fails.
    public func writeData(_ data: Data, to url: URL) throws {
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }
    
    /// Safely moves a file from a legacy location to a new destination.
    ///
    /// If the destination file already exists, the legacy file is safely removed.
    ///
    /// - Parameters:
    ///   - sourceURL: Source file URL.
    ///   - destinationURL: Destination file URL.
    public func migrateFile(from sourceURL: URL, to destinationURL: URL) {
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            do {
                try fileManager.removeItem(at: sourceURL)
                logd("Evicted duplicate legacy file at \(sourceURL.lastPathComponent)")
            } catch {
                loge("Failed to purge duplicate legacy file: \(error.localizedDescription)")
            }
            return
        }
        
        let parentDir = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            logi("Migrated legacy cache: \(sourceURL.lastPathComponent) -> \(destinationURL.lastPathComponent)")
        } catch {
            loge("Failed to migrate legacy cache: \(error.localizedDescription)")
        }
    }
    
    /// Concurrently checks existence of multiple target URLs, filtering down to items present on disk.
    ///
    /// - Parameter urls: Candidate file URLs to test.
    /// - Returns: Sub-collection of file URLs that currently exist.
    public func filterExistingFiles(among urls: [URL]) -> [URL] {
        urls.filter { fileManager.fileExists(atPath: $0.path) }
    }
    
    /// Safely deletes files at target URLs without throwing on missing items.
    ///
    /// - Parameter urls: Files to permanently purge.
    public func removeFiles(at urls: [URL]) {
        for url in urls {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
                logd("Purged cache file: \(url.lastPathComponent)")
            } catch {
                loge("Failed to purge cache file \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
    
    /// Removes a directory and all of its contents, recreating an empty replacement directory in its place.
    ///
    /// - Parameter directoryURL: Target folder to wipe.
    public func wipeAndRecreateDirectory(at directoryURL: URL) {
        do {
            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            logi("Purged cache directory: \(directoryURL.lastPathComponent)")
        } catch {
            loge("Failed to wipe cache directory: \(error.localizedDescription)")
        }
    }
    
    /// Computes the aggregate byte size of all files residing directly or recursively within a directory.
    ///
    /// - Parameter directoryURL: Root folder to calculate.
    /// - Returns: Total size in bytes.
    public func calculateDirectorySize(at directoryURL: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            totalSize += Int64(size)
        }
        return totalSize
    }
    
    /// Synchronously calculates the aggregate file size across the provided directories.
    ///
    /// - Parameter directories: Target cache directories.
    /// - Returns: Total size in bytes.
    public func calculateTotalSize(in directories: [URL]) -> Int64 {
        var total: Int64 = 0
        for dir in directories {
            if let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        total += Int64(size)
                    }
                }
            }
        }
        return total
    }
    
    /// Evicts oldest accessed files (FIFO) within a directory until total size falls below `limitBytes`.
    ///
    /// - Parameters:
    ///   - directory: Target directory to sweep.
    ///   - limitBytes: Maximum allowed aggregate size in bytes.
    ///   - protectedURLs: File URLs that must be shielded from eviction.
    public func evictFilesIfNeeded(in directory: URL, limitBytes: Int64, keeping protectedURLs: Set<URL> = []) {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var files: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "part" {
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                    logd("Failed to remove part file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { continue }
            let fileSize = Int64(size)
            let date = values.contentModificationDate ?? Date.distantPast
            totalSize += fileSize
            files.append((url: fileURL, size: fileSize, date: date))
        }
        
        guard totalSize > limitBytes else { return }
        
        // Sort oldest first (FIFO eviction)
        files.sort { $0.date < $1.date }
        
        for file in files {
            if totalSize <= limitBytes { break }
            if protectedURLs.contains(file.url) { continue }
            do {
                try fileManager.removeItem(at: file.url)
                totalSize -= file.size
            } catch {
                logd("Failed to evict file \(file.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
    
    /// Removes orphaned partial download files (`.part`) older than the given duration.
    ///
    /// - Parameters:
    ///   - directories: The directories to inspect for stale `.part` files.
    ///   - seconds: Age threshold in seconds.
    public func cleanOrphanedPartFiles(in directories: [URL], olderThan seconds: TimeInterval = 3600) {
        let now = Date()
        for dir in directories {
            guard let enumerator = fileManager.enumerator(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "part" {
                if let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   now.timeIntervalSince(modDate) > seconds {
                    do {
                        try fileManager.removeItem(at: fileURL)
                    } catch {
                        logd("Failed to remove stale part file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    /// Clears all files in the designated directories, optionally sparing protected URLs.
    ///
    /// - Parameters:
    ///   - directories: The cache directories to purge and recreate.
    ///   - protectedURLs: URLs that must be preserved.
    public func clearDirectories(_ directories: [URL], protectedURLs: Set<URL> = []) {
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        for dir in directories {
            if protectedURLs.isEmpty {
                do {
                    try fileManager.removeItem(at: dir)
                } catch {
                    logd("Failed to remove cache directory \(dir.lastPathComponent): \(error.localizedDescription)")
                }
            } else {
                if let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: nil) {
                    for case let fileURL as URL in enumerator where !protecting(fileURL, in: protectedURLs) {
                        do {
                            try fileManager.removeItem(at: fileURL)
                        } catch {
                            logd("Failed to remove file during clear \(fileURL.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                }
            }
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: attributes)
            } catch {
                loge("Failed to recreate cache directory \(dir.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
    
    private func protecting(_ url: URL, in protectedURLs: Set<URL>) -> Bool {
        protectedURLs.contains(url)
    }
    
    /// Performs an LRU eviction pass over a cache directory, pruning oldest files until storage drops below target capacity.
    ///
    /// - Parameters:
    ///   - directoryURL: The directory to prune.
    ///   - maxSizeBytes: Target high-water ceiling in bytes.
    ///   - protectedURLs: Active file URLs currently locked against eviction.
    public func pruneDirectory(at directoryURL: URL, maxSizeBytes: Int64, protectedURLs: Set<URL> = []) {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        struct FileEntry {
            let url: URL
            let size: Int64
            let date: Date
        }
        
        var entries: [FileEntry] = []
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            
            let date = values.contentAccessDate ?? values.contentModificationDate ?? .distantPast
            entries.append(FileEntry(url: fileURL, size: Int64(size), date: date))
            totalSize += Int64(size)
        }
        
        guard totalSize > maxSizeBytes else { return }
        
        // Sort oldest first (LRU eviction order)
        entries.sort { $0.date < $1.date }
        
        for entry in entries {
            guard totalSize > maxSizeBytes else { break }
            guard !protectedURLs.contains(entry.url) else { continue }
            
            do {
                try fileManager.removeItem(at: entry.url)
                totalSize -= entry.size
                logd("Evicted LRU cache file: \(entry.url.lastPathComponent) (\(entry.size) bytes)")
            } catch {
                loge("Failed to evict LRU file \(entry.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
