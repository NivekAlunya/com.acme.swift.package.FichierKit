//
//  SMBVideoThumbnailLoader.swift
//  FichierKit
//
//

import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// Actor-isolated video thumbnail generator and bounded in-memory `NSCache` for `FichierKit` media items.
///
/// Generates frame thumbnails for both native (`AVAssetImageGenerator` via direct `smbstream://`
/// `AVAssetResourceLoaderDelegate` or local file URLs) and extended (`VLCKit` via `SMBStreamingServer`)
/// containers, while strictly respecting tvOS memory constraints and cooperative task cancellation.
public actor SMBVideoThumbnailLoader {
    public static let shared = SMBVideoThumbnailLoader()

    /// Canonical bounding pixel dimension shared across list rows and grid cards to avoid duplicate fetches.
    public static let standardMaxDimension: CGFloat = 560

    #if canImport(UIKit)
    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    #endif

    private let localLimiter = SMBVideoThumbnailLimiter(maxConcurrent: 2)
    private let smbLimiter = SMBVideoThumbnailLimiter(maxConcurrent: 1)

    public init() {}

    #if canImport(UIKit)
    /// Generates or returns a cached thumbnail for a remote SMB video item.
    public func loadThumbnail(
        sourceID: String,
        share: String,
        path: String,
        fileName: String,
        fileSize: Int64,
        targetSize: CGSize = CGSize(width: 380, height: 260),
        resolver: any MediaSourceResolverProtocol = DefaultMediaSourceResolver.shared
    ) async -> UIImage? {
        let ext = Self.fileExtension(fileName: fileName, fallbackPath: path)
        guard SupportedMediaTypes.isVideo(extension: ext) else {
            return nil
        }

        let maxDimension = Self.canonicalDimension(for: targetSize)
        let cacheKey = "\(sourceID)|\(share)/\(path)|vidthumb|\(Int(maxDimension))"
        if let cached = cachedThumbnail(forKey: cacheKey) {
            return cached
        }

        // Brief debounce to avoid saturating SMB sockets when rapidly scrolling down a folder.
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled else { return nil }

        if let cached = cachedThumbnail(forKey: cacheKey) {
            return cached
        }

        guard let sharesSource = await resolver.resolve(sourceID: sourceID) as? SharesMediaSource else {
            return nil
        }

        let image = await fetchSMBThumbnail(
            sharesSource: sharesSource,
            share: share,
            path: path,
            fileName: fileName,
            fileSize: fileSize,
            fileExtension: ext,
            maxDimension: maxDimension,
            cacheKey: cacheKey
        )

        if let image, !Task.isCancelled {
            storeThumbnail(image, forKey: cacheKey)
        }

        return image
    }

    /// Generates or returns a cached thumbnail for a local video file URL.
    public func loadThumbnail(
        from localURL: URL,
        fileName: String? = nil,
        targetSize: CGSize = CGSize(width: 380, height: 260)
    ) async -> UIImage? {
        guard localURL.isFileURL, !Task.isCancelled else { return nil }

        let resolvedName = fileName ?? localURL.lastPathComponent
        let ext = Self.fileExtension(fileName: resolvedName, fallbackPath: localURL.path)
        guard SupportedMediaTypes.isVideo(extension: ext) else {
            return nil
        }

        let maxDimension = Self.canonicalDimension(for: targetSize)
        let cacheKey = "local|\(localURL.standardizedFileURL.path)|vidthumb|\(Int(maxDimension))"
        if let cached = cachedThumbnail(forKey: cacheKey) {
            return cached
        }

        let image = try? await localLimiter.withPermit {
            guard !Task.isCancelled else { return nil as UIImage? }
            if let cached = await self.cachedThumbnail(forKey: cacheKey) {
                return cached
            }
            return await Self.extractLocalThumbnail(
                from: localURL,
                fileExtension: ext,
                maxDimension: maxDimension
            )
        }

        if let image, !Task.isCancelled {
            storeThumbnail(image, forKey: cacheKey)
        }

        return image
    }

    /// Clears all cached in-memory video thumbnails.
    public func clearCache() {
        thumbnailCache.removeAllObjects()
    }

    private func cachedThumbnail(forKey key: String) -> UIImage? {
        thumbnailCache.object(forKey: key as NSString)
    }

    private func storeThumbnail(_ image: UIImage, forKey key: String) {
        let estimatedCost = Int(image.size.width * image.size.height * 4)
        thumbnailCache.setObject(image, forKey: key as NSString, cost: max(1, estimatedCost))
    }

    // MARK: - Private SMB Stream Fetching

    private func fetchSMBThumbnail(
        sharesSource: SharesMediaSource,
        share: String,
        path: String,
        fileName: String,
        fileSize: Int64,
        fileExtension: String,
        maxDimension: CGFloat,
        cacheKey: String
    ) async -> UIImage? {
        try? await smbLimiter.withPermit {
            guard !Task.isCancelled else { return nil as UIImage? }
            if let cached = await self.cachedThumbnail(forKey: cacheKey) {
                return cached
            }

            let resolvedSize: Int64
            if fileSize > 0 {
                resolvedSize = fileSize
            } else {
                resolvedSize = (try? await sharesSource.client.fileSize(share: share, path: path)) ?? 0
            }

            guard resolvedSize > 0, !Task.isCancelled else {
                return nil
            }

            return await Self.extractSMBFrame(
                client: sharesSource.client,
                share: share,
                path: path,
                fileName: fileName,
                fileSize: resolvedSize,
                maxDimension: maxDimension
            )
        }
    }

    /// Extracts a representative frame from a remote SMB video, bypassing cache and concurrency limiting.
    ///
    /// Native containers try `AVFoundation` first and fall back to `VLCKit`; extended containers
    /// (MKV, AVI, WebM, ...) use the reverse order. Callers own caching and concurrency policy.
    public nonisolated static func extractSMBFrame(
        client: any SMBClientProtocol,
        share: String,
        path: String,
        fileName: String,
        fileSize: Int64,
        maxDimension: CGFloat = standardMaxDimension
    ) async -> UIImage? {
        guard fileSize > 0, !Task.isCancelled else { return nil }
        let ext = fileExtension(fileName: fileName, fallbackPath: path)
        if !SupportedMediaTypes.isExtendedVideo(extension: ext) {
            if let nativeImage = await extractWithSMBAVFoundation(
                client: client, share: share, path: path, fileName: fileName,
                fileSize: fileSize, maxDimension: maxDimension, timeoutSeconds: 12.0
            ) {
                return nativeImage
            }
            guard !Task.isCancelled else { return nil }
            return await extractWithSMBStreamingServer(
                client: client, share: share, path: path, fileName: fileName,
                fileSize: fileSize, maxDimension: maxDimension, preferVLC: true
            )
        }
        if let extendedImage = await extractWithSMBStreamingServer(
            client: client, share: share, path: path, fileName: fileName,
            fileSize: fileSize, maxDimension: maxDimension, preferVLC: true
        ) {
            return extendedImage
        }
        guard !Task.isCancelled else { return nil }
        return await extractWithSMBAVFoundation(
            client: client, share: share, path: path, fileName: fileName,
            fileSize: fileSize, maxDimension: maxDimension, timeoutSeconds: 8.0
        )
    }

    // MARK: - Frame Extraction Pipeline

    private nonisolated static func canonicalDimension(for targetSize: CGSize) -> CGFloat {
        let requested = max(targetSize.width, targetSize.height)
        return requested > standardMaxDimension ? min(800, requested) : standardMaxDimension
    }

    private nonisolated static func fileExtension(fileName: String, fallbackPath: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if !ext.isEmpty {
            return ext
        }
        return (fallbackPath as NSString).pathExtension.lowercased()
    }

    private nonisolated static func extractLocalThumbnail(
        from url: URL,
        fileExtension: String,
        maxDimension: CGFloat
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        if SupportedMediaTypes.isExtendedVideo(extension: fileExtension) {
            if let vlcImage = await extractWithVLC(from: url, maxDimension: maxDimension) {
                return vlcImage
            }
            guard !Task.isCancelled else { return nil }
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            return await extractWithAVFoundation(asset: asset, maxDimension: maxDimension, timeoutSeconds: 8.0)
        } else {
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            if let avImage = await extractWithAVFoundation(asset: asset, maxDimension: maxDimension, timeoutSeconds: 10.0) {
                return avImage
            }
            guard !Task.isCancelled else { return nil }
            return await extractWithVLC(from: url, maxDimension: maxDimension)
        }
    }

    private nonisolated static func extractWithSMBAVFoundation(
        client: any SMBClientProtocol,
        share: String,
        path: String,
        fileName: String,
        fileSize: Int64,
        maxDimension: CGFloat,
        timeoutSeconds: Double
    ) async -> UIImage? {
        guard !Task.isCancelled, fileSize > 0 else { return nil }

        let streamURL = SMBAVAssetResourceLoaderDelegate.makeStreamURL(fileName: fileName)
        let delegate = SMBAVAssetResourceLoaderDelegate(
            client: client,
            share: share,
            path: path,
            fileName: fileName,
            fileSize: fileSize
        )
        // swiftlint:disable:next no_legacy_dispatch_queue
        let loaderQueue = DispatchQueue(label: "com.fichierkit.smb.thumb.\(UUID().uuidString)")
        let asset = AVURLAsset(url: streamURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        asset.resourceLoader.setDelegate(delegate, queue: loaderQueue)

        defer {
            delegate.cancelAll()
            asset.cancelLoading()
            asset.resourceLoader.setDelegate(nil, queue: nil)
        }

        let result = await withTaskCancellationHandler {
            await extractWithAVFoundation(
                asset: asset,
                maxDimension: maxDimension,
                timeoutSeconds: timeoutSeconds,
                onAbort: { delegate.cancelAll() }
            )
        } onCancel: {
            delegate.cancelAll()
        }
        // AVURLAsset only holds the resource-loader delegate weakly; keep delegate and queue alive until extraction finishes.
        withExtendedLifetime((delegate, loaderQueue)) {}
        return result
    }

    private nonisolated static func extractWithSMBStreamingServer(
        client: any SMBClientProtocol,
        share: String,
        path: String,
        fileName: String,
        fileSize: Int64,
        maxDimension: CGFloat,
        preferVLC: Bool
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        let server = SMBStreamingServer(
            client: client,
            share: share,
            path: path,
            fileName: fileName,
            totalSize: fileSize
        )

        do {
            let streamURL = try await server.start()
            if Task.isCancelled {
                await server.stop()
                return nil
            }

            let image: UIImage?
            if preferVLC {
                image = await extractWithVLC(from: streamURL, maxDimension: maxDimension)
            } else {
                let asset = AVURLAsset(url: streamURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
                image = await extractWithAVFoundation(asset: asset, maxDimension: maxDimension, timeoutSeconds: 10.0)
            }

            await server.stop()
            return image
        } catch {
            await server.stop()
            return nil
        }
    }

    private nonisolated static func extractWithAVFoundation(
        asset: AVURLAsset,
        maxDimension: CGFloat,
        timeoutSeconds: Double,
        onAbort: (@Sendable () -> Void)? = nil
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        // Race the extraction against a timeout: AVFoundation can hang indefinitely on files it
        // cannot parse over a custom loader. The first child to finish wins and the other is
        // cancelled. `onAbort` additionally cancels in-flight SMB reads so the socket is freed.
        return await withTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                await renderAVAssetFrame(asset: asset, maxDimension: maxDimension)
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                onAbort?()
                return nil
            }

            let firstResult = (await group.next()).flatMap { $0 }
            group.cancelAll()
            return firstResult
        }
    }

    private nonisolated static func renderAVAssetFrame(asset: AVURLAsset, maxDimension: CGFloat) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        let durationSeconds = try? await asset.load(.duration).seconds
        guard !Task.isCancelled else { return nil }

        let (targetTime, tolerance) = resolveSampleTiming(durationSeconds: durationSeconds)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        if let (cgImage, _) = try? await generator.image(at: targetTime) {
            return UIImage(cgImage: cgImage)
        }

        guard !Task.isCancelled, targetTime > .zero else { return nil }

        // Fallback when the preferred time cannot be decoded (e.g. file shorter than reported):
        // accept any nearby keyframe at the very start.
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        if let (cgImage, _) = try? await generator.image(at: .zero) {
            return UIImage(cgImage: cgImage)
        }

        return nil
    }

    /// Picks the frame to sample and how far from it AVFoundation may snap (looser tolerance = faster,
    /// as it can decode the nearest keyframe). Avoids the first frame, which is often black: 10 s into
    /// long videos, 25% into medium ones, and frame zero for clips of 2 s or less.
    private nonisolated static func resolveSampleTiming(durationSeconds: Double?) -> (CMTime, CMTime) {
        guard let durationSeconds, durationSeconds.isFinite, !durationSeconds.isNaN, durationSeconds > 0 else {
            return (CMTime(seconds: 10.0, preferredTimescale: 600), CMTime(seconds: 2.5, preferredTimescale: 600))
        }

        if durationSeconds > 12.0 {
            return (CMTime(seconds: 10.0, preferredTimescale: 600), CMTime(seconds: 2.5, preferredTimescale: 600))
        } else if durationSeconds > 2.0 {
            return (CMTime(seconds: durationSeconds * 0.25, preferredTimescale: 600), CMTime(seconds: 1.5, preferredTimescale: 600))
        } else {
            return (.zero, .positiveInfinity)
        }
    }

    private nonisolated static func extractWithVLC(
        from url: URL,
        maxDimension: CGFloat
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        if let thumb = await VLCVideoThumbnailActor.shared.generateThumbnail(
            from: url,
            maxDimension: maxDimension,
            snapshotPosition: 0.05,
            timeoutSeconds: 10.0
        ) {
            return thumb
        }

        guard !Task.isCancelled else { return nil }

        return await VLCVideoThumbnailActor.shared.generateThumbnail(
            from: url,
            maxDimension: maxDimension,
            snapshotPosition: 0.0,
            timeoutSeconds: 8.0
        )
    }
    #else
    public func loadThumbnail(
        sourceID: String,
        share: String,
        path: String,
        fileName: String,
        fileSize: Int64,
        targetSize: CGSize = CGSize(width: 380, height: 260),
        resolver: any MediaSourceResolverProtocol = DefaultMediaSourceResolver.shared
    ) async -> Any? {
        nil
    }

    public func loadThumbnail(
        from localURL: URL,
        fileName: String? = nil,
        targetSize: CGSize = CGSize(width: 380, height: 260)
    ) async -> Any? {
        nil
    }

    public func clearCache() {}
    #endif
}
