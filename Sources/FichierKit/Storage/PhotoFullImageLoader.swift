//
//  PhotoFullImageLoader.swift
//  FichierKit
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Photos)
import Photos
#endif

/// An isolated actor managing high-resolution PhotoKit image loading with cancellation.
public actor PhotoFullImageLoader {
    public static let shared = PhotoFullImageLoader()

    #if canImport(Photos)
    private let imageManager = PHCachingImageManager()
    private var activeRequests: [String: PHImageRequestID] = [:]
    #endif

    public init() {}

    #if canImport(UIKit) && canImport(Photos)
    /// Loads a high-resolution image for the specified PhotoKit local identifier.
    ///
    /// - Parameters:
    ///   - assetIdentifier: The `PHAsset.localIdentifier`.
    ///   - maxDimension: Maximum pixel width/height (defaults to 3840 for 4K tvOS displays).
    /// - Returns: Full resolution `UIImage` or `nil` on failure/cancellation.
    public func loadFullImage(for assetIdentifier: String, maxDimension: CGFloat = 3840) async -> UIImage? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        let targetSize = CGSize(width: maxDimension, height: maxDimension)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .fast

                var hasResumed = false

                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { [weak self] image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    let error = info?[PHImageErrorKey] as? Error

                    if !hasResumed && (!isDegraded || isCancelled || error != nil) {
                        hasResumed = true
                        continuation.resume(returning: image)
                        Task { [weak self] in
                            await self?.cleanupRequest(for: assetIdentifier)
                        }
                    }
                }

                self.activeRequests[assetIdentifier] = requestID
            }
        } onCancel: {
            Task {
                await self.cancelRequest(for: assetIdentifier)
            }
        }
    }

    /// Aborts an ongoing full-resolution image request.
    public func cancelRequest(for assetIdentifier: String) {
        if let requestID = activeRequests.removeValue(forKey: assetIdentifier) {
            imageManager.cancelImageRequest(requestID)
        }
    }

    private func cleanupRequest(for assetIdentifier: String) {
        activeRequests.removeValue(forKey: assetIdentifier)
    }
    #else
    public func loadFullImage(for assetIdentifier: String, maxDimension: CGFloat = 3840) async -> Any? {
        nil
    }

    public func cancelRequest(for assetIdentifier: String) {}
    #endif
}
