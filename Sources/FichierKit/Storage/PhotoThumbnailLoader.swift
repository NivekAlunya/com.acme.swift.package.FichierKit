//
//  PhotoThumbnailLoader.swift
//  FichierKit
//

import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Photos)
import Photos
#endif

/// An isolated actor managing asynchronous PhotoKit thumbnail decoding and video poster fallback retrieval.
///
/// Supports cooperative task cancellation so thumbnail requests are cleanly aborted
/// when scrolling past items on tvOS.
public actor PhotoThumbnailLoader {
    public static let shared = PhotoThumbnailLoader()

    #if canImport(Photos)
    private let imageManager = PHCachingImageManager()
    #endif

    public init() {}

    #if canImport(UIKit) && canImport(Photos)
    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 150
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    /// Requests a downsampled thumbnail image for a given PhotoKit local identifier.
    ///
    /// - Parameters:
    ///   - assetIdentifier: The `PHAsset.localIdentifier`.
    ///   - targetSize: Desired thumbnail pixel dimensions.
    /// - Returns: Decoded `UIImage` or `nil` if aborted/failed.
    public func loadThumbnail(for assetIdentifier: String, targetSize: CGSize) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        let standardDim = SMBVideoThumbnailLoader.standardMaxDimension
        let requestedDim = max(targetSize.width, targetSize.height)
        let canonicalDim = requestedDim > standardDim ? min(800, requestedDim) : standardDim
        let cacheKey = "\(assetIdentifier)|\(Int(canonicalDim))"

        if let cached = thumbnailCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        let pixelTargetSize = CGSize(width: canonicalDim, height: canonicalDim)

        if let image = await Self.requestImageThumbnail(
            manager: imageManager,
            asset: asset,
            targetSize: pixelTargetSize
        ) {
            storeThumbnail(image, forKey: cacheKey)
            return image
        }

        guard !Task.isCancelled, asset.mediaType == .video else {
            return nil
        }

        if let fallbackImage = await Self.requestVideoFrameFallback(
            manager: imageManager,
            asset: asset,
            targetSize: pixelTargetSize
        ) {
            storeThumbnail(fallbackImage, forKey: cacheKey)
            return fallbackImage
        }

        return nil
    }

    /// Clears all in-memory cached PhotoKit thumbnails.
    public func clearCache() {
        thumbnailCache.removeAllObjects()
    }

    private func storeThumbnail(_ image: UIImage, forKey key: String) {
        let estimatedCost = Int(image.size.width * image.size.height * 4)
        thumbnailCache.setObject(image, forKey: key as NSString, cost: max(1, estimatedCost))
    }

    private nonisolated static func requestImageThumbnail(
        manager: PHCachingImageManager,
        asset: PHAsset,
        targetSize: CGSize
    ) async -> UIImage? {
        let stream = AsyncStream<UIImage?> { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isSynchronous = false

            let requestID = manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error

                if !isDegraded || isCancelled || error != nil {
                    continuation.yield(image)
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination {
                    manager.cancelImageRequest(requestID)
                }
            }
        }

        for await image in stream {
            return image
        }
        return nil
    }

    private nonisolated static func requestVideoFrameFallback(
        manager: PHCachingImageManager,
        asset: PHAsset,
        targetSize: CGSize
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        let stream = AsyncStream<UIImage?> { continuation in
            let videoOptions = PHVideoRequestOptions()
            videoOptions.isNetworkAccessAllowed = true
            videoOptions.deliveryMode = .mediumQualityFormat

            let requestID = manager.requestAVAsset(
                forVideo: asset,
                options: videoOptions
            ) { avAsset, _, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? Error

                if let avAsset {
                    let generator = AVAssetImageGenerator(asset: avAsset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = targetSize
                    generator.requestedTimeToleranceBefore = .positiveInfinity
                    generator.requestedTimeToleranceAfter = .positiveInfinity
                    generator.generateCGImageAsynchronously(for: .zero) { cgImage, _, _ in
                        continuation.yield(cgImage.map { UIImage(cgImage: $0) })
                        continuation.finish()
                    }
                } else if !isDegraded || isCancelled || error != nil {
                    continuation.yield(nil)
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination {
                    manager.cancelImageRequest(requestID)
                }
            }
        }

        for await image in stream {
            return image
        }
        return nil
    }
    #else
    public func loadThumbnail(for assetIdentifier: String, targetSize: CGSize) async -> Any? {
        nil
    }

    public func clearCache() {}

    public func cancelRequest(for assetIdentifier: String) {}
    #endif
}
