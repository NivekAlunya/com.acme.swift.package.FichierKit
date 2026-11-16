//
//  MediaDetailStore.swift
//  FichierKit
//
//

import Foundation
import AVFoundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(Photos) && !os(tvOS)
import Photos
#endif

/// Thread-safe coordinator and memory cache providing lightweight, non-blocking media metadata
/// descriptors (video duration, image frame dimensions, and PDF page counts) for list and grid cells.
@MainActor
public final class MediaDetailStore: Sendable {
    /// Shared singleton instance.
    public static let shared = MediaDetailStore()

    /// Shared queue used by AVAssetResourceLoader delegate callbacks during video metadata probing.
    // swiftlint:disable:next no_legacy_dispatch_queue
    private static let videoProbeQueue = DispatchQueue(label: "com.fichierkit.detail.videoProbe", qos: .utility)

    /// In-memory cache holding resolved detail strings keyed by item ID.
    private let cache: NSCache<NSString, NSString> = {
        let c = NSCache<NSString, NSString>()
        c.countLimit = 2000
        return c
    }()

    /// Tracks in-flight metadata extraction tasks to deduplicate concurrent requests for the same media item.
    private var inFlightTasks: [String: Task<String?, Never>] = [:]

    public init() {}

    // MARK: - Synchronous Cache Access

    /// Returns the cached media detail string immediately if available in memory.
    public func cachedDetail(for itemID: String) -> String? {
        cache.object(forKey: itemID as NSString) as String?
    }

    /// Stores a resolved media detail descriptor in the in-memory cache.
    public func registerDetail(_ detail: String, for itemID: String) {
        guard !detail.isEmpty else { return }
        cache.setObject(detail as NSString, forKey: itemID as NSString)
    }

    /// Clears all cached media detail records.
    public func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Asynchronous Resolution

    /// Resolves and returns a human-readable media detail string (video time, image dimensions, or PDF page count).
    ///
    /// Executes lightweight, zero-decode operations (EXIF header parse, PDF catalog count, or moov atom duration)
    /// without consuming significant CPU or blocking scrolling performance.
    public func resolveDetail(
        for item: MediaSourceItem,
        resolver: (any MediaSourceResolverProtocol)? = nil
    ) async -> String? {
        if let cached = cachedDetail(for: item.id) {
            return cached
        }

        if let existing = inFlightTasks[item.id] {
            return await existing.value
        }

        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.performResolution(for: item, resolver: resolver)
        }

        inFlightTasks[item.id] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: item.id)

        if let result, !result.isEmpty {
            registerDetail(result, for: item.id)
        }

        return result
    }

    // MARK: - Internal Resolution Logic

    private func performResolution(
        for item: MediaSourceItem,
        resolver: (any MediaSourceResolverProtocol)?
    ) async -> String? {
        guard !Task.isCancelled, item.type != .folder else { return nil }

        // 1. PhotoKit Library Asset (instantaneous metadata lookup)
        #if canImport(Photos) && !os(tvOS)
        if let phID = item.phAssetIdentifier {
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [phID], options: nil)
            if let asset = fetch.firstObject {
                if asset.mediaType == .video {
                    return MediaFormatHelper.formatDuration(asset.duration)
                } else if asset.mediaType == .image {
                    return MediaFormatHelper.formatDimensions(width: asset.pixelWidth, height: asset.pixelHeight)
                }
            }
            return nil
        }
        #endif

        // 2. Local File URL (header-only parses)
        if let localURL = item.localURL {
            return await resolveLocalURLDetail(url: localURL, name: item.name)
        }

        // 3. Remote SMB Item
        return await resolveRemoteSMBDetail(for: item, resolver: resolver)
    }

    private func resolveLocalURLDetail(url: URL, name: String) async -> String? {
        guard !Task.isCancelled else { return nil }
        let ext = (name as NSString).pathExtension.lowercased()

        if SupportedMediaTypes.isVideo(extension: ext) {
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            if let dur = try? await asset.load(.duration).seconds, dur > 0 {
                return MediaFormatHelper.formatDuration(dur)
            }
        } else if SupportedMediaTypes.isImage(extension: ext) {
            return await Task.detached(priority: .utility) {
                Self.parseLocalImageDimensions(url: url)
            }.value
        }

        return nil
    }

    private func resolveRemoteSMBDetail(
        for item: MediaSourceItem,
        resolver: (any MediaSourceResolverProtocol)?
    ) async -> String? {
        guard !Task.isCancelled else { return nil }
        guard let sourceID = item.sourceID,
              let share = item.smbShare,
              let path = item.smbPath else {
            return nil
        }

        let effectiveResolver = resolver ?? DefaultMediaSourceResolver.shared
        guard let sharesSource = await effectiveResolver.resolve(sourceID: sourceID) as? SharesMediaSource else {
            return nil
        }

        let ext = (item.name as NSString).pathExtension.lowercased()

        if SupportedMediaTypes.isImage(extension: ext) {
            // Read first 64 KB prefix: sufficient for EXIF header metadata
            let prefix = try? await sharesSource.client.readFileData(
                share: share,
                path: path,
                maxBytes: 65536
            )
            guard let prefix, !prefix.isEmpty else { return nil }

            return await Task.detached(priority: .utility) {
                Self.parsePrefixImageDimensions(data: prefix)
            }.value
        } else if SupportedMediaTypes.isVideo(extension: ext) && !SupportedMediaTypes.isExtendedVideo(extension: ext) {
            // Fast AVURLAsset probe over SMBAVAssetResourceLoaderDelegate with strict 1.5s timeout
            let streamURL = SMBAVAssetResourceLoaderDelegate.makeStreamURL(fileName: item.name)
            let delegate = SMBAVAssetResourceLoaderDelegate(
                client: sharesSource.client,
                share: share,
                path: path,
                fileName: item.name,
                fileSize: item.size
            )
            let asset = AVURLAsset(url: streamURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            asset.resourceLoader.setDelegate(delegate, queue: Self.videoProbeQueue)

            defer {
                delegate.cancelAll()
                asset.cancelLoading()
                asset.resourceLoader.setDelegate(nil, queue: nil)
            }

            let dur = await withTaskGroup(of: Double?.self) { group in
                group.addTask {
                    try? await asset.load(.duration).seconds
                }
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(1500))
                    // Cancel delegate and asset immediately on timeout to abort network I/O and unblock group join
                    delegate.cancelAll()
                    asset.cancelLoading()
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            withExtendedLifetime(delegate) {}

            if let dur, dur > 0 {
                return MediaFormatHelper.formatDuration(dur)
            }
        }

        return nil
    }

    // MARK: - Non-isolated Background Image Parsers

    private nonisolated static func parseLocalImageDimensions(url: URL) -> String? {
        #if canImport(ImageIO)
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int
        let h = props[kCGImagePropertyPixelHeight] as? Int
        if let w, let h, w > 0, h > 0 {
            return MediaFormatHelper.formatDimensions(width: w, height: h)
        }
        #endif
        return nil
    }

    private nonisolated static func parsePrefixImageDimensions(data: Data) -> String? {
        #if canImport(ImageIO)
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int
        let h = props[kCGImagePropertyPixelHeight] as? Int
        if let w, let h, w > 0, h > 0 {
            return MediaFormatHelper.formatDimensions(width: w, height: h)
        }
        #endif
        return nil
    }
}
