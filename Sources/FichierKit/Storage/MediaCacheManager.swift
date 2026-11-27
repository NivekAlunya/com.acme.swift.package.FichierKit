//
//  MediaCacheManager.swift
//  FichierKit
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import AVFoundation
import CryptoKit
import Wappn
#if canImport(PDFKit) && !os(tvOS)
import PDFKit
#endif

/// Centralized on-disk caching engine managing thumbnail persistence, video stream buffering, and document staging.
///
/// ### Architecture & Concurrency Overview
/// - **Thread Safety & Concurrency**: Conforms to `Sendable` as an immutable coordinator with atomic filesystem operations.
///   Heavy I/O calculations (directory sweeps, eviction, size summation) execute on background detached tasks (`priority: .utility`).
/// - **Universal Master Thumbnail Dimension (420px)**: Employs a single master dimension of 420 px for all cached thumbnails.
///   Whether the user displays List, Compact Grid (120px), Medium Grid (180px), or Large Grid (280px), a single cached file
///   satisfies all views with native CoreGraphics scaling, eliminating duplicate downloads and multiple cache files per photo.
/// - **Dynamic Host Disk Budgeting**: Continuously probes available volume space via `volumeAvailableCapacityForImportantUsageKey`.
///   Under low disk conditions (< 1.5 GB free), cache ceilings automatically contract from 2 GB to 400 MB (videos)
///   and 300 MB to 100 MB (thumbnails) to prevent device storage warnings.
/// - **FIFO / Protected Eviction**: Evicts oldest accessed files first, while strictly shielding currently active URLs (`protectedURLs`).
nonisolated public final class MediaCacheManager: Sendable {
    
    /// Global shared singleton coordinator.
    public static let shared = MediaCacheManager()
    
    /// Underlying system `FileManager` reference.
    var fileManager: FileManager { .default }
    
    /// Isolated actor serializing all background disk mutations, file migrations, and evictions.
    public let diskActor: MediaDiskCacheActor
    
    /// Local directory storing JPEG downsampled thumbnails.
    public let thumbnailsDirectory: URL
    
    /// Local directory caching downloaded video files and streaming buffers.
    public let videosDirectory: URL
    
    /// Local directory staging cached PDF documents.
    public let documentsDirectory: URL
    
    // MARK: - Initialization & Directory Bootstrap
    
    /// Initializes directories inside the user's `CachesDirectory` sandbox with `.completeUntilFirstUserAuthentication` protection.
    ///
    /// Automatically kicks off an asynchronous background maintenance pass to prune orphaned partial downloads.
    public init() {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let thumbs = caches.appendingPathComponent("SMBThumbnails", isDirectory: true)
        let vids = caches.appendingPathComponent("SMBVideos", isDirectory: true)
        let docs = caches.appendingPathComponent("SMBDocuments", isDirectory: true)
        
        self.thumbnailsDirectory = thumbs
        self.videosDirectory = vids
        self.documentsDirectory = docs
        self.diskActor = MediaDiskCacheActor.shared
        
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        for directory in [thumbs, vids, docs] {
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
            } catch {
                loge("Failed to create cache directory \(directory.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        Task(priority: .background) { [self] in
            await self.performMaintenanceSweepAsync()
        }
    }
    
    // MARK: - Thumbnail Master Dimension
    
    /// The universal master pixel dimension for all on-disk cached thumbnails (560px).
    public static let standardThumbnailDimension: CGFloat = 560
    
    // MARK: - Key Hashing
    
    /// Computes a cryptographically stable SHA-256 cache key for an image thumbnail.
    ///
    /// - Parameters:
    ///   - shareName: Name of the SMB share or storage root.
    ///   - path: Canonical path to the file.
    ///   - dimension: Pixel dimension bounding box.
    ///   - connectionID: Connection identifier scoping multi-server configurations.
    /// - Returns: A 64-character lowercase hexadecimal hash string.
    public func cacheKey(for shareName: String, path: String, dimension: CGFloat = MediaCacheManager.standardThumbnailDimension, connectionID: String = "") -> String {
        let raw: String
        if connectionID.isEmpty {
            raw = "\(shareName)::\(path)_\(Int(dimension))"
        } else {
            raw = "\(connectionID)|\(shareName)::\(path)_\(Int(dimension))"
        }
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Computes a SHA-256 hash key for a video file cache location.
    ///
    /// - Parameters:
    ///   - shareName: Storage root or share name.
    ///   - path: Canonical path to the video file.
    ///   - connectionID: Scoped connection ID.
    /// - Returns: A 64-character hexadecimal hash string.
    public func videoKey(for shareName: String, path: String, connectionID: String = "") -> String {
        let raw: String
        if connectionID.isEmpty {
            raw = "\(shareName)::\(path)"
        } else {
            raw = "\(connectionID)|\(shareName)::\(path)"
        }
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Resolves primary, legacy, and fallback lookup keys for thumbnail cache reads.
    ///
    /// - Parameters:
    ///   - shareName: Storage root or share name.
    ///   - path: Canonical path to the item.
    ///   - dimension: Target display dimension.
    ///   - connectionID: Scoped connection profile ID.
    /// - Returns: A tuple of primary, unscoped fallback, and dimension-specific legacy keys.
    public func thumbnailKeys(
        for shareName: String,
        path: String,
        dimension: CGFloat = MediaCacheManager.standardThumbnailDimension,
        connectionID: String = ""
    ) -> (primary: String, fallback: String?, legacyDimensionKey: String?) {
        let standardDim = Self.standardThumbnailDimension
        let primary = cacheKey(for: shareName, path: path, dimension: standardDim, connectionID: connectionID)
        let fallback = !connectionID.isEmpty ? cacheKey(for: shareName, path: path, dimension: standardDim, connectionID: "") : nil
        let legacyDimKey = (Int(dimension) != Int(standardDim)) ? cacheKey(for: shareName, path: path, dimension: dimension, connectionID: connectionID) : nil
        return (primary, fallback, legacyDimKey)
    }
    
    /// Resolves all candidate on-disk URLs where a thumbnail could exist.
    public func thumbnailURLs(for shareName: String, path: String, connectionID: String = "") -> [URL] {
        let (photoDiskKey, photoFallbackKey, photoLegacyKey) = thumbnailKeys(
            for: shareName,
            path: path,
            dimension: Self.standardThumbnailDimension,
            connectionID: connectionID
        )
        return [photoDiskKey, photoFallbackKey, photoLegacyKey].compactMap { $0 }.map {
            thumbnailsDirectory.appendingPathComponent("\($0).jpg")
        }
    }
    
    // MARK: - Thumbnail Disk Cache Operations
    
    #if canImport(UIKit)
    /// Synchronously retrieves a cached thumbnail image from disk.
    ///
    /// Checks primary key, and automatically migrates legacy unscoped keys if discovered.
    ///
    /// - Parameters:
    ///   - key: The primary SHA-256 key.
    ///   - fallbackKey: Legacy unscoped key.
    ///   - legacyKey: Dimension-specific key.
    /// - Returns: Decoded `UIImage`, or `nil` if not cached.
    public func getThumbnail(for key: String, fallbackKey: String? = nil, legacyKey: String? = nil) -> UIImage? {
        let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            return image
        }
        
        // Fallback to legacy key and migrate file to new scoped key atomically
        if let fallbackKey, fallbackKey != key {
            let legacyURL = thumbnailsDirectory.appendingPathComponent("\(fallbackKey).jpg")
            if fileManager.fileExists(atPath: legacyURL.path),
               let data = try? Data(contentsOf: legacyURL),
               let image = UIImage(data: data) {
                if !fileManager.fileExists(atPath: fileURL.path) {
                    do {
                        try fileManager.moveItem(at: legacyURL, to: fileURL)
                    } catch {
                        logw("Failed to migrate legacy cached thumbnail \(legacyURL.lastPathComponent): \(error.localizedDescription)")
                    }
                } else {
                    try? fileManager.removeItem(at: legacyURL)
                }
                return image
            }
        }
        
        // Fallback to older dimension-specific cache (e.g. 140, 200, 280) if standard 420 hasn't been generated yet
        if let legacyKey, legacyKey != key, legacyKey != fallbackKey {
            let legacyURL = thumbnailsDirectory.appendingPathComponent("\(legacyKey).jpg")
            if fileManager.fileExists(atPath: legacyURL.path),
               let data = try? Data(contentsOf: legacyURL),
               let image = UIImage(data: data) {
                return image
            }
        }
        
        return nil
    }
    #endif
    
    /// Checks whether a cached thumbnail file exists on local disk for the given key.
    ///
    /// - Parameter key: The SHA-256 cache key.
    /// - Returns: `true` if the thumbnail file is present; `false` otherwise.
    public func hasThumbnail(for key: String) -> Bool {
        let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    #if canImport(UIKit)
    /// Asynchronously retrieves a cached thumbnail from disk off the caller's executor via `MediaDiskCacheActor`.
    public func getThumbnailAsync(for key: String, fallbackKey: String? = nil, legacyKey: String? = nil) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        if let data = await diskActor.readData(from: fileURL), let image = UIImage(data: data) {
            return image
        }
        guard !Task.isCancelled else { return nil }
        if let fallbackKey {
            let fallbackURL = thumbnailsDirectory.appendingPathComponent("\(fallbackKey).jpg")
            if let data = await diskActor.readData(from: fallbackURL), let image = UIImage(data: data) {
                return image
            }
        }
        guard !Task.isCancelled else { return nil }
        if let legacyKey, legacyKey != key, legacyKey != fallbackKey {
            let legacyURL = thumbnailsDirectory.appendingPathComponent("\(legacyKey).jpg")
            if let data = await diskActor.readData(from: legacyURL), let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }
    
    /// Writes an image thumbnail to disk as an atomic JPEG file (82% compression quality).
    ///
    /// - Parameters:
    ///   - image: The `UIImage` to encode.
    ///   - key: The SHA-256 cache key.
    public func saveThumbnail(_ image: UIImage, for key: String) {
        let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            loge("Failed to write thumbnail to disk: \(error.localizedDescription)")
        }
    }
    
    /// Asynchronously saves an image thumbnail to disk isolated on `MediaDiskCacheActor`.
    public func saveThumbnailAsync(_ image: UIImage, for key: String) async {
        let fileURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        do {
            try await diskActor.writeData(data, to: fileURL)
        } catch {
            loge("Failed to write thumbnail asynchronously: \(error.localizedDescription)")
        }
    }
    #endif
    
    // MARK: - Video & Document Path Resolution
    
    /// Resolves the on-disk file URL for a cached video file.
    public func localVideoURL(shareName: String, path: String, filename: String, connectionID: String = "") -> URL {
        let key = videoKey(for: shareName, path: path, connectionID: connectionID)
        let ext = (filename as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "mp4" : ext
        return videosDirectory.appendingPathComponent("\(key).\(safeExt)")
    }
    
    /// Asynchronously migrates legacy unscoped video caches to the scoped canonical path.
    public func migrateLegacyVideoIfNeeded(shareName: String, path: String, filename: String, connectionID: String = "") async {
        guard !connectionID.isEmpty else { return }
        let canonicalURL = localVideoURL(shareName: shareName, path: path, filename: filename, connectionID: connectionID)
        guard !fileManager.fileExists(atPath: canonicalURL.path) else { return }
        let ext = (filename as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "mp4" : ext
        let legacyKey = videoKey(for: shareName, path: path, connectionID: "")
        let legacyURL = videosDirectory.appendingPathComponent("\(legacyKey).\(safeExt)")
        await diskActor.migrateFile(from: legacyURL, to: canonicalURL)
    }
    
    /// Checks whether a full video file is currently cached and complete on local disk.
    public func hasCachedVideo(shareName: String, path: String, filename: String, connectionID: String = "") -> Bool {
        let url = localVideoURL(shareName: shareName, path: path, filename: filename, connectionID: connectionID)
        return fileManager.fileExists(atPath: url.path)
    }
    
    /// Resolves the on-disk file URL for a cached PDF document.
    public func localDocumentURL(shareName: String, path: String, filename: String, connectionID: String = "") -> URL {
        let key = videoKey(for: shareName, path: path, connectionID: connectionID)
        let ext = (filename as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "pdf" : ext
        return documentsDirectory.appendingPathComponent("\(key).\(safeExt)")
    }
    
    /// Checks whether a complete copy of a document is cached on disk.
    public func hasCachedDocument(shareName: String, path: String, filename: String, connectionID: String = "") -> Bool {
        let url = localDocumentURL(shareName: shareName, path: path, filename: filename, connectionID: connectionID)
        return fileManager.fileExists(atPath: url.path)
    }
    
    // MARK: - MediaSourceItem Conveniences
    
    /// Resolves the canonical on-disk cached video URL for a `MediaSourceItem`.
    public func localVideoURL(for item: MediaSourceItem) -> URL {
        localVideoURL(
            shareName: item.smbShare ?? "",
            path: item.smbPath ?? item.path,
            filename: item.name,
            connectionID: item.sourceID ?? ""
        )
    }
    
    /// Checks whether a full video file is currently cached for a `MediaSourceItem`.
    public func hasCachedVideo(for item: MediaSourceItem) -> Bool {
        hasCachedVideo(
            shareName: item.smbShare ?? "",
            path: item.smbPath ?? item.path,
            filename: item.name,
            connectionID: item.sourceID ?? ""
        )
    }
    
    /// Resolves the on-disk file URL for a cached document for a `MediaSourceItem`.
    public func localDocumentURL(for item: MediaSourceItem) -> URL {
        localDocumentURL(
            shareName: item.smbShare ?? "",
            path: item.smbPath ?? item.path,
            filename: item.name,
            connectionID: item.sourceID ?? ""
        )
    }
    
    /// Checks whether a complete copy of a document is cached for a `MediaSourceItem`.
    public func hasCachedDocument(for item: MediaSourceItem) -> Bool {
        hasCachedDocument(
            shareName: item.smbShare ?? "",
            path: item.smbPath ?? item.path,
            filename: item.name,
            connectionID: item.sourceID ?? ""
        )
    }
    
    // MARK: - PDF Thumbnail Generation
    
    #if canImport(PDFKit) && canImport(UIKit) && !os(tvOS)
    /// Renders the first page of a PDF document at the given URL into a thumbnail.
    ///
    /// - Parameters:
    ///   - url: File URL of the PDF document.
    ///   - maxDimension: Maximum thumbnail pixel size.
    /// - Returns: A rendered `UIImage` cover image, or `nil` on failure.
    public func generatePDFThumbnail(from url: URL, maxDimension: CGFloat = standardThumbnailDimension) -> UIImage? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let size = CGSize(width: maxDimension, height: maxDimension)
        return page.thumbnail(of: size, for: .mediaBox)
    }
    
    /// Renders the first page of an active parsed `PDFDocument` instance into a thumbnail.
    ///
    /// - Parameters:
    ///   - doc: The parsed `PDFDocument` instance.
    ///   - maxDimension: Maximum thumbnail pixel size.
    /// - Returns: A rendered `UIImage` cover image, or `nil` on failure.
    public func generatePDFThumbnail(from doc: PDFDocument, maxDimension: CGFloat = standardThumbnailDimension) -> UIImage? {
        guard let page = doc.page(at: 0) else { return nil }
        let size = CGSize(width: maxDimension, height: maxDimension)
        return page.thumbnail(of: size, for: .mediaBox)
    }
    
    /// Renders a PDF cover thumbnail from an in-memory byte buffer.
    ///
    /// For payloads exceeding 5 MB, stages to temporary disk storage to utilize virtual memory
    /// mapping (`mmap`) via `PDFDocument(url:)`, avoiding large dirty heap spikes during rasterization.
    /// For payloads $\le 5\text{ MB}$ (including 1 MB fast-path prefix reads), decodes purely in-memory.
    ///
    /// - Parameters:
    ///   - data: The raw PDF byte data.
    ///   - maxDimension: Maximum thumbnail pixel size.
    /// - Returns: A rendered `UIImage` cover image, or `nil` on failure.
    public func generatePDFThumbnail(from data: Data, maxDimension: CGFloat = standardThumbnailDimension) -> UIImage? {
        if data.isEmpty { return nil }
        if data.count > 5 * 1024 * 1024 {
            let tempURL = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
            do {
                try data.write(to: tempURL, options: .atomic)
                defer { try? fileManager.removeItem(at: tempURL) }
                return generatePDFThumbnail(from: tempURL, maxDimension: maxDimension)
            } catch {
                // Fall back to in-memory decoding if temporary write fails
            }
        }
        guard let doc = PDFDocument(data: data), let page = doc.page(at: 0) else { return nil }
        let size = CGSize(width: maxDimension, height: maxDimension)
        return page.thumbnail(of: size, for: .mediaBox)
    }
    #elseif canImport(UIKit)
    public func generatePDFThumbnail(from url: URL, maxDimension: CGFloat = standardThumbnailDimension) -> UIImage? {
        nil
    }
    public func generatePDFThumbnail(from data: Data, maxDimension: CGFloat = standardThumbnailDimension) -> UIImage? {
        nil
    }
    #endif
    
    // MARK: - Video Thumbnail Timing Constants
    
    /// The default timestamp sampled for video thumbnails (15.0s) to avoid black introductory frames.
    public static let defaultVideoThumbnailTime = CMTime(seconds: 15.0, preferredTimescale: 600)
    
    /// The keyframe tolerance applied when sampling video thumbnails (2.5s) to allow instant I-frame decoding.
    public static let defaultVideoThumbnailTolerance = CMTime(seconds: 2.5, preferredTimescale: 600)
    
    /// Fallback timestamp when the video is shorter than the default thumbnail time.
    public static let fallbackVideoThumbnailTime = CMTime(seconds: 0.5, preferredTimescale: 600)
    
    // MARK: - Video Thumbnail Generation
    
    #if canImport(UIKit)
    /// Generates a video thumbnail frame from a local file using `AVAssetImageGenerator`.
    ///
    /// First attempts preferred keyframe time (15s); if that fails or video is shorter, falls back to frame zero.
    ///
    /// - Parameters:
    ///   - localURL: The local video file URL.
    ///   - maxDimension: Maximum pixel bounding box.
    ///   - preferredTime: Target timestamp.
    /// - Returns: A rendered `UIImage`, or `nil` on failure.
    public func generateVideoThumbnail(
        from localURL: URL,
        maxDimension: CGFloat = standardThumbnailDimension,
        preferredTime: CMTime = defaultVideoThumbnailTime
    ) async -> UIImage? {
        if SupportedMediaTypes.isExtendedVideo(extension: localURL.pathExtension) {
            return await generateExtendedVideoThumbnail(from: localURL, maxDimension: maxDimension, preferredTime: preferredTime)
        }
        
        let asset = AVURLAsset(url: localURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = Self.defaultVideoThumbnailTolerance
        generator.requestedTimeToleranceAfter = Self.defaultVideoThumbnailTolerance
        
        // 1. Try preferred time (defaults to 15.0s):
        if let (cgImage, _) = try? await generator.image(at: preferredTime) {
            return UIImage(cgImage: cgImage)
        }
        
        // 2. Fallback to keyframe at zero (e.g. for short videos < 15s):
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
    
    /// Generates a video thumbnail frame for an extended video file (MKV, AVI, WebM, etc.).
    public func generateExtendedVideoThumbnail(
        from localURL: URL,
        maxDimension: CGFloat = standardThumbnailDimension,
        preferredTime: CMTime = defaultVideoThumbnailTime
    ) async -> UIImage? {
        let initialPosition: Float = preferredTime <= .zero ? 0.0 : 0.02
        if let thumb = await VLCVideoThumbnailActor.shared.generateThumbnail(
            from: localURL,
            maxDimension: maxDimension,
            snapshotPosition: initialPosition,
            timeoutSeconds: 4.0
        ) {
            return thumb
        }
        
        // If a non-zero timestamp was requested and failed, fall back to keyframe zero
        if preferredTime > .zero {
            if let thumb = await VLCVideoThumbnailActor.shared.generateThumbnail(
                from: localURL,
                maxDimension: maxDimension,
                snapshotPosition: 0.0,
                timeoutSeconds: 4.0
            ) {
                return thumb
            }
        }
        
        let asset = AVURLAsset(url: localURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        if let (cgImage, _) = try? await generator.image(at: preferredTime) {
            return UIImage(cgImage: cgImage)
        }
        if let (cgImage, _) = try? await generator.image(at: .zero) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
    #endif
}
