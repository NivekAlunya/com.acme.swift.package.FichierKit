//
//  SMBImageLoader.swift
//  FichierKit
//
//

import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

/// Actor-isolated SMB thumbnail and full-image loader using memory-only bounded `NSCache`
/// to comply with tvOS storage constraints while maintaining smooth scrolling and 4K quality.
public actor SMBImageLoader {
    public static let shared = SMBImageLoader()

    #if canImport(UIKit)
    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 48 * 1024 * 1024 // 48 MB bounded thumbnail cache
        return cache
    }()

    private let fullImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 96 * 1024 * 1024 // 96 MB bounded 4K image cache
        return cache
    }()
    #endif

    private let maxThumbnailDownloadBytes: Int64 = 25 * 1024 * 1024
    private let maxFullImageDownloadBytes: Int64 = 50 * 1024 * 1024
    private let downloadLimiter = SMBVideoThumbnailLimiter(maxConcurrent: 2)

    public init() {}

    #if canImport(UIKit)
    /// Loads and downsamples an SMB image file for thumbnail presentation without writing to disk.
    public func loadThumbnail(
        sourceID: String,
        share: String,
        path: String,
        targetSize: CGSize,
        resolver: any MediaSourceResolverProtocol = DefaultMediaSourceResolver.shared
    ) async -> UIImage? {
        let ext = (path as NSString).pathExtension.lowercased()
        guard SupportedMediaTypes.isImage(extension: ext) else {
            return nil
        }

        let maxPixelSize = Self.canonicalThumbnailDimension(for: targetSize)
        let cacheKey = "\(sourceID)|\(share)/\(path)|thumb|\(Int(maxPixelSize))"
        if let cached = cachedThumbnail(forKey: cacheKey) {
            return cached
        }

        guard !Task.isCancelled else { return nil }
        guard let sharesSource = await resolver.resolve(sourceID: sourceID) as? SharesMediaSource else {
            return nil
        }

        return try? await downloadLimiter.withPermit {
            guard !Task.isCancelled else { return nil as UIImage? }
            if let cached = await self.cachedThumbnail(forKey: cacheKey) {
                return cached
            }

            guard let data = try? await sharesSource.client.readFileData(
                share: share,
                path: path,
                maxBytes: self.maxThumbnailDownloadBytes
            ) else {
                return nil
            }

            guard !Task.isCancelled, !data.isEmpty else { return nil }
            guard let decoded = Self.decodeDownsampledImage(from: data, maxPixelSize: maxPixelSize) else {
                return nil
            }

            await self.storeThumbnail(decoded, forKey: cacheKey)
            return decoded
        }
    }

    private func cachedThumbnail(forKey key: String) -> UIImage? {
        thumbnailCache.object(forKey: key as NSString)
    }

    private func storeThumbnail(_ image: UIImage, forKey key: String) {
        let estimatedCost = Int(image.size.width * image.size.height * 4)
        thumbnailCache.setObject(image, forKey: key as NSString, cost: max(1, estimatedCost))
    }

    private nonisolated static func canonicalThumbnailDimension(for targetSize: CGSize) -> CGFloat {
        let requested = max(targetSize.width, targetSize.height) * 2
        return requested > SMBVideoThumbnailLoader.standardMaxDimension
            ? min(800, requested)
            : SMBVideoThumbnailLoader.standardMaxDimension
    }

    /// Loads and downsamples a local image file for thumbnail presentation without hitting the network.
    public func loadLocalThumbnail(url: URL, targetSize: CGSize) async -> UIImage? {
        guard url.isFileURL, !Task.isCancelled else { return nil }
        let ext = url.pathExtension.lowercased()
        guard SupportedMediaTypes.isImage(extension: ext) else {
            return nil
        }

        let maxPixelSize = Self.canonicalThumbnailDimension(for: targetSize)
        let cacheKey = "local|\(url.standardizedFileURL.path)|thumb|\(Int(maxPixelSize))" as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              !Task.isCancelled,
              !data.isEmpty,
              let decoded = Self.decodeDownsampledImage(from: data, maxPixelSize: maxPixelSize) else {
            return nil
        }

        let estimatedCost = Int(decoded.size.width * decoded.size.height * 4)
        thumbnailCache.setObject(decoded, forKey: cacheKey, cost: max(1, estimatedCost))
        return decoded
    }

    /// Loads a full-resolution (up to 4K display bounds) SMB image for full-screen viewing.
    public func loadFullImage(
        sourceID: String,
        share: String,
        path: String,
        maxDimension: CGFloat = 3840,
        resolver: any MediaSourceResolverProtocol = DefaultMediaSourceResolver.shared
    ) async -> UIImage? {
        let ext = (path as NSString).pathExtension.lowercased()
        guard SupportedMediaTypes.isImage(extension: ext) else {
            return nil
        }

        let cacheKey = "\(sourceID)|\(share)/\(path)|full|\(Int(maxDimension))" as NSString
        if let cached = fullImageCache.object(forKey: cacheKey) {
            return cached
        }

        guard !Task.isCancelled else { return nil }
        guard let sharesSource = await resolver.resolve(sourceID: sourceID) as? SharesMediaSource else {
            return nil
        }

        guard let data = try? await sharesSource.client.readFileData(
            share: share,
            path: path,
            maxBytes: maxFullImageDownloadBytes
        ) else {
            return nil
        }

        guard !Task.isCancelled, !data.isEmpty else { return nil }
        guard let decoded = Self.decodeDownsampledImage(from: data, maxPixelSize: maxDimension) else {
            return nil
        }

        let estimatedCost = Int(decoded.size.width * decoded.size.height * 4)
        fullImageCache.setObject(decoded, forKey: cacheKey, cost: max(1, estimatedCost))
        return decoded
    }

    /// Clears all cached in-memory SMB images to free RAM cleanly.
    public func clearCache() {
        thumbnailCache.removeAllObjects()
        fullImageCache.removeAllObjects()
    }

    private nonisolated static func decodeDownsampledImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return UIImage(data: data)
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(data: data)
    }
    #else
    public func loadThumbnail(
        sourceID: String,
        share: String,
        path: String,
        targetSize: CGSize,
        resolver: any MediaSourceResolverProtocol = DefaultMediaSourceResolver.shared
    ) async -> Any? {
        nil
    }

    public func loadLocalThumbnail(url: URL, targetSize: CGSize) async -> Any? {
        nil
    }

    public func loadFullImage(
        sourceID: String,
        share: String,
        path: String,
        maxDimension: CGFloat = 3840,
        resolver: any MediaSourceResolverProtocol = DefaultMediaSourceResolver.shared
    ) async -> Any? {
        nil
    }

    public func clearCache() {}
    #endif
}
