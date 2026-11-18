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

    #if canImport(UIKit) && canImport(Photos)
    private let imageManager = PHCachingImageManager()
    private var activeRequestIDs: [UUID: (assetID: String, requestID: PHImageRequestID)] = [:]
    private var pendingContinuations: [UUID: CheckedContinuation<UIImage?, Never>] = [:]
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
        guard !Task.isCancelled else { return nil }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        let targetSize = CGSize(width: maxDimension, height: maxDimension)
        let token = UUID()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }

                self.pendingContinuations[token] = continuation

                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .fast

                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { [weak self] image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    let error = info?[PHImageErrorKey] as? Error

                    if !isDegraded || isCancelled || error != nil {
                        Task { [weak self] in
                            await self?.handleCompletion(
                                token: token,
                                image: (isCancelled || error != nil) ? nil : image
                            )
                        }
                    }
                }

                if self.pendingContinuations[token] != nil {
                    self.activeRequestIDs[token] = (assetIdentifier, requestID)
                }
            }
        } onCancel: {
            Task {
                await self.cancelRequest(token: token)
            }
        }
    }

    /// Aborts an ongoing full-resolution image request.
    public func cancelRequest(for assetIdentifier: String) {
        let matchingTokens = activeRequestIDs.compactMap { token, value in
            value.assetID == assetIdentifier ? token : nil
        }
        for token in matchingTokens {
            cancelRequest(token: token)
        }
    }

    private func cancelRequest(token: UUID) {
        if let (_, requestID) = activeRequestIDs.removeValue(forKey: token) {
            imageManager.cancelImageRequest(requestID)
        }
        if let continuation = pendingContinuations.removeValue(forKey: token) {
            continuation.resume(returning: nil)
        }
    }

    private func handleCompletion(token: UUID, image: UIImage?) {
        guard let continuation = pendingContinuations.removeValue(forKey: token) else {
            return
        }
        activeRequestIDs.removeValue(forKey: token)
        continuation.resume(returning: image)
    }
    #else
    public func loadFullImage(for assetIdentifier: String, maxDimension: CGFloat = 3840) async -> Any? {
        nil
    }

    public func cancelRequest(for assetIdentifier: String) {}
    #endif
}
