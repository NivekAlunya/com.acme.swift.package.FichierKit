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
        Task { [diskActor, videosDirectory, documentsDirectory] in
            await diskActor.cleanOrphanedPartFiles(in: [videosDirectory, documentsDirectory], olderThan: seconds)
        }
    }
    
    /// Performs a full disk cache maintenance pass, purging partial downloads and enforcing dynamic capacity ceilings.
    ///
    /// - Parameter protecting: Set of URLs (such as currently playing videos) that must not be evicted.
    public func performMaintenanceSweep(protecting: Set<URL> = []) {
        Task { [weak self] in
            await self?.performMaintenanceSweepAsync(protecting: protecting)
        }
    }
    
    /// Asynchronously runs `performMaintenanceSweep` isolated on `MediaDiskCacheActor`.
    public func performMaintenanceSweepAsync(protecting: Set<URL> = []) async {
        let freeSpace = systemAvailableFreeSpace()
        let isLowDiskSpace = freeSpace < 1_500_000_000
        
        let videoLimit: Int64 = isLowDiskSpace ? 400_000_000 : 2_000_000_000
        let docLimit: Int64 = isLowDiskSpace ? 200_000_000 : 1_000_000_000
        let thumbLimit: Int64 = isLowDiskSpace ? 100_000_000 : 300_000_000
        
        // Each step is independent, so cancellation (e.g. background time expiring) can stop between them.
        guard !Task.isCancelled else { return }
        await diskActor.cleanOrphanedPartFiles(in: [videosDirectory, documentsDirectory])
        guard !Task.isCancelled else { return }
        await diskActor.evictFilesIfNeeded(in: videosDirectory, limitBytes: videoLimit, keeping: protecting)
        guard !Task.isCancelled else { return }
        await diskActor.evictFilesIfNeeded(in: documentsDirectory, limitBytes: docLimit, keeping: protecting)
        guard !Task.isCancelled else { return }
        await diskActor.evictFilesIfNeeded(in: thumbnailsDirectory, limitBytes: thumbLimit)
    }

    /// Evicts oldest cached video files (FIFO) if total video cache size exceeds `limitBytes` (default 2 GB).
    ///
    /// - Parameters:
    ///   - limitBytes: Maximum allowed aggregate size in bytes.
    ///   - protectedURLs: File URLs that must be shielded from eviction.
    public func evictVideosIfNeeded(limitBytes: Int64 = 2_000_000_000, keeping protectedURLs: Set<URL> = []) {
        Task { [diskActor, videosDirectory] in
            await diskActor.evictFilesIfNeeded(in: videosDirectory, limitBytes: limitBytes, keeping: protectedURLs)
        }
    }
    
    /// Evicts oldest cached document files (FIFO) if total document cache size exceeds `limitBytes` (default 1 GB).
    ///
    /// - Parameters:
    ///   - limitBytes: Maximum allowed aggregate size in bytes.
    ///   - protectedURLs: File URLs that must be shielded from eviction.
    public func evictDocumentsIfNeeded(limitBytes: Int64 = 1_000_000_000, keeping protectedURLs: Set<URL> = []) {
        Task { [diskActor, documentsDirectory] in
            await diskActor.evictFilesIfNeeded(in: documentsDirectory, limitBytes: limitBytes, keeping: protectedURLs)
        }
    }
    
    /// Evicts oldest cached thumbnails if aggregate thumbnail cache exceeds `limitBytes` (default 300 MB).
    public func evictThumbnailsIfNeeded(limitBytes: Int64 = 300_000_000) {
        Task { [diskActor, thumbnailsDirectory] in
            await diskActor.evictFilesIfNeeded(in: thumbnailsDirectory, limitBytes: limitBytes)
        }
    }
    
    /// Computes aggregate cache size in bytes asynchronously isolated on `MediaDiskCacheActor`.
    public func calculateTotalCacheSize() async -> Int64 {
        await diskActor.calculateTotalSize(in: [thumbnailsDirectory, videosDirectory, documentsDirectory])
    }
    
    /// Asynchronously formats the aggregate disk cache size into a human-readable string (e.g. "124.5 MB").
    public func formattedCacheSize() async -> String {
        let bytes = await calculateTotalCacheSize()
        return MediaFormatHelper.formatByteCount(bytes)
    }
    
    /// Deletes all cached thumbnails and videos, optionally protecting designated URLs.
    public func clearAllCache(protecting: Set<URL> = []) {
        Task { [weak self] in
            await self?.clearAllCacheAsync(protecting: protecting)
        }
    }
    
    /// Asynchronous wrapper for `clearAllCache` executed safely on `MediaDiskCacheActor`.
    public func clearAllCacheAsync(protecting: Set<URL> = []) async {
        await diskActor.clearDirectories([thumbnailsDirectory, documentsDirectory], protectedURLs: [])
        await diskActor.clearDirectories([videosDirectory], protectedURLs: protecting)
    }
}
