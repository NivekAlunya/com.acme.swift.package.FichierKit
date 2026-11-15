//
//  MediaCacheManager+Eviction.swift
//  FichierKit
//

import Foundation
import Wappn

extension MediaCacheManager {
    
    // MARK: - Cache Size, Eviction & Cleanup
    
    /// Queries the filesystem to determine free available volume space in bytes.
    public func systemAvailableFreeSpace() -> Int64 {
        let cachesURL = thumbnailsDirectory
        #if !os(tvOS)
        if let values = try? cachesURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        #endif
        if let values = try? cachesURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return Int64.max
    }
    
    /// Cleans up any orphaned partial download files (`.part`) older than the given duration (default 1 hour).
    public func cleanOrphanedPartFiles(olderThan seconds: TimeInterval = 3600) {
        let now = Date()
        for dir in [videosDirectory, documentsDirectory] {
            guard let enumerator = fileManager.enumerator(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "part" {
                if let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   now.timeIntervalSince(modDate) > seconds {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        }
    }
    
    /// Performs a full disk cache maintenance pass, purging partial downloads and enforcing dynamic capacity ceilings.
    ///
    /// - Parameter protecting: Set of URLs (such as currently playing videos) that must not be evicted.
    public func performMaintenanceSweep(protecting: Set<URL> = []) {
        cleanOrphanedPartFiles()
        
        let freeSpace = systemAvailableFreeSpace()
        let isLowDiskSpace = freeSpace < 1_500_000_000
        
        // Dynamically adjust disk budget according to host volume capacity
        let videoLimit: Int64 = isLowDiskSpace ? 400_000_000 : 2_000_000_000
        let docLimit: Int64 = isLowDiskSpace ? 200_000_000 : 1_000_000_000
        let thumbLimit: Int64 = isLowDiskSpace ? 100_000_000 : 300_000_000
        
        evictVideosIfNeeded(limitBytes: videoLimit, keeping: protecting)
        evictDocumentsIfNeeded(limitBytes: docLimit, keeping: protecting)
        evictThumbnailsIfNeeded(limitBytes: thumbLimit)
    }
    
    /// Asynchronously runs `performMaintenanceSweep` isolated on `MediaDiskCacheActor`.
    public func performMaintenanceSweepAsync(protecting: Set<URL> = []) async {
        let freeSpace = systemAvailableFreeSpace()
        let isLowDiskSpace = freeSpace < 1_500_000_000
        
        let videoLimit: Int64 = isLowDiskSpace ? 400_000_000 : 2_000_000_000
        let docLimit: Int64 = isLowDiskSpace ? 200_000_000 : 1_000_000_000
        let thumbLimit: Int64 = isLowDiskSpace ? 100_000_000 : 300_000_000
        
        await diskActor.cleanOrphanedPartFiles(in: [videosDirectory, documentsDirectory])
        await diskActor.evictFilesIfNeeded(in: videosDirectory, limitBytes: videoLimit, keeping: protecting)
        await diskActor.evictFilesIfNeeded(in: documentsDirectory, limitBytes: docLimit, keeping: protecting)
        await diskActor.evictFilesIfNeeded(in: thumbnailsDirectory, limitBytes: thumbLimit)
    }
    
    /// Evicts oldest cached video files (FIFO) if total video cache size exceeds `limitBytes` (default 2 GB).
    ///
    /// - Parameters:
    ///   - limitBytes: Maximum allowed aggregate size in bytes.
    ///   - protectedURLs: File URLs that must be shielded from eviction.
    public func evictVideosIfNeeded(limitBytes: Int64 = 2_000_000_000, keeping protectedURLs: Set<URL> = []) {
        guard let enumerator = fileManager.enumerator(
            at: videosDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var videoFiles: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "part" {
                try? fileManager.removeItem(at: fileURL)
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { continue }
            let fileSize = Int64(size)
            let date = values.contentModificationDate ?? Date.distantPast
            totalSize += fileSize
            videoFiles.append((url: fileURL, size: fileSize, date: date))
        }
        
        guard totalSize > limitBytes else { return }
        
        // Sort oldest first (FIFO eviction)
        videoFiles.sort { $0.date < $1.date }
        
        for file in videoFiles {
            if totalSize <= limitBytes { break }
            if protectedURLs.contains(file.url) { continue }
            do {
                try fileManager.removeItem(at: file.url)
                totalSize -= file.size
            } catch {
                // Ignore failure to remove individual item
            }
        }
    }
    
    /// Evicts oldest cached document files (FIFO) if total document cache size exceeds `limitBytes` (default 1 GB).
    ///
    /// - Parameters:
    ///   - limitBytes: Maximum allowed aggregate size in bytes.
    ///   - protectedURLs: File URLs that must be shielded from eviction.
    public func evictDocumentsIfNeeded(limitBytes: Int64 = 1_000_000_000, keeping protectedURLs: Set<URL> = []) {
        guard let enumerator = fileManager.enumerator(
            at: documentsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var docFiles: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "part" {
                try? fileManager.removeItem(at: fileURL)
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { continue }
            let fileSize = Int64(size)
            let date = values.contentModificationDate ?? Date.distantPast
            totalSize += fileSize
            docFiles.append((url: fileURL, size: fileSize, date: date))
        }
        
        guard totalSize > limitBytes else { return }
        
        // Sort oldest first (FIFO eviction)
        docFiles.sort { $0.date < $1.date }
        
        for file in docFiles {
            if totalSize <= limitBytes { break }
            if protectedURLs.contains(file.url) { continue }
            do {
                try fileManager.removeItem(at: file.url)
                totalSize -= file.size
            } catch {
                // Ignore failure to remove individual item
            }
        }
    }
    
    /// Evicts oldest cached thumbnails if aggregate thumbnail cache exceeds `limitBytes` (default 300 MB).
    public func evictThumbnailsIfNeeded(limitBytes: Int64 = 300_000_000) {
        guard let enumerator = fileManager.enumerator(
            at: thumbnailsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var thumbFiles: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { continue }
            let fileSize = Int64(size)
            let date = values.contentModificationDate ?? Date.distantPast
            totalSize += fileSize
            thumbFiles.append((url: fileURL, size: fileSize, date: date))
        }
        
        guard totalSize > limitBytes else { return }
        
        thumbFiles.sort { $0.date < $1.date }
        
        for file in thumbFiles {
            if totalSize <= limitBytes { break }
            do {
                try fileManager.removeItem(at: file.url)
                totalSize -= file.size
            } catch {
                // Ignore failure to remove individual item
            }
        }
    }
    
    /// Computes aggregate cache size in bytes asynchronously isolated on `MediaDiskCacheActor`.
    public func calculateTotalCacheSize() async -> Int64 {
        await diskActor.calculateTotalSize(in: [thumbnailsDirectory, videosDirectory, documentsDirectory])
    }
    
    /// Asynchronously formats the aggregate disk cache size into a human-readable string (e.g. "124.5 MB").
    public func formattedCacheSize() async -> String {
        let bytes = await calculateTotalCacheSize()
        return formatByteCount(bytes)
    }
    
    /// Converts a byte integer into a localized string.
    private func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Deletes all cached thumbnails and videos, optionally protecting designated URLs.
    public func clearAllCache(protecting: Set<URL> = []) {
        try? fileManager.removeItem(at: thumbnailsDirectory)
        try? fileManager.removeItem(at: documentsDirectory)
        
        if protecting.isEmpty {
            try? fileManager.removeItem(at: videosDirectory)
        } else {
            if let enumerator = fileManager.enumerator(at: videosDirectory, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator where !protecting.contains(fileURL) {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        }
        
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        try? fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true, attributes: attributes)
        try? fileManager.createDirectory(at: videosDirectory, withIntermediateDirectories: true, attributes: attributes)
        try? fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: attributes)
    }
    
    /// Asynchronous wrapper for `clearAllCache` executed safely on `MediaDiskCacheActor`.
    public func clearAllCacheAsync(protecting: Set<URL> = []) async {
        await diskActor.clearDirectories([thumbnailsDirectory, documentsDirectory], protectedURLs: [])
        await diskActor.clearDirectories([videosDirectory], protectedURLs: protecting)
    }
}
