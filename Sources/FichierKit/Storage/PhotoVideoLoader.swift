//
//  PhotoVideoLoader.swift
//  FichierKit
//
//

import Foundation
#if canImport(Photos)
import Photos
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Actor-isolated loader resolving playable video URLs for PhotoKit assets via `PHImageManager`.
///
/// Direct file assets return their `AVURLAsset.url` immediately. Multi-segment compositions (e.g. Slow-Mo)
/// are exported to an ephemeral `.mov` in a pruned temporary directory to respect tvOS storage limits.
public actor PhotoVideoLoader {
    public static let shared = PhotoVideoLoader()

    private var exportDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fichiertv_video_exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public init() {}

    #if canImport(Photos) && canImport(AVFoundation)
    /// Resolves a playable local URL for the specified `PHAsset.localIdentifier`.
    public func loadVideoURL(for assetIdentifier: String) async throws -> URL {
        try Task.checkCancellation()
        purgeOldExports()

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            throw NSError(
                domain: "PhotoVideoLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Video asset not found in Photos library."]
            )
        }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        let tempExportURL = exportDirectory.appendingPathComponent("ph_export_\(UUID().uuidString).mov")

        // PhotoKit delivers the asset through a callback (possibly several times: a degraded preview
        // first, then the final asset). The stream bridges that callback to async/await and yields a
        // *deferred resolver* closure, so the potentially long export runs in the caller's task
        // (cancellable) rather than inside the PhotoKit callback.
        let stream = AsyncThrowingStream<@Sendable () async throws -> URL, any Error> { continuation in
            let requestID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if isCancelled || Task.isCancelled {
                    continuation.finish(throwing: CancellationError())
                    return
                }

                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.finish(throwing: error)
                    return
                }

                // Plain video files are file-backed and can be played in place with no export.
                // Compositions (Slow-Mo, edited clips) have no single file and must be exported.
                if let urlAsset = avAsset as? AVURLAsset {
                    let directURL = urlAsset.url
                    continuation.yield { directURL }
                    continuation.finish()
                    return
                }

                guard let avAsset else {
                    // A nil asset with the "degraded" flag is an intermediate callback; wait for the final one.
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if !isDegraded {
                        continuation.finish(throwing: NSError(
                            domain: "PhotoVideoLoader",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Unable to load video asset from Photos library."]
                        ))
                    }
                    return
                }

                guard let exporter = AVAssetExportSession(
                    asset: avAsset,
                    presetName: AVAssetExportPresetHighestQuality
                ) else {
                    continuation.finish(throwing: NSError(
                        domain: "PhotoVideoLoader",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to initialize video export session."]
                    ))
                    return
                }

                let box = PhotoExportSessionBox(session: exporter)
                continuation.yield {
                    try await box.session.export(to: tempExportURL, as: .mov)
                    return tempExportURL
                }
                continuation.finish()
            }

            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    PHImageManager.default().cancelImageRequest(requestID)
                }
            }
        }

        var iterator = stream.makeAsyncIterator()
        do {
            guard let resolveURL = try await iterator.next() else {
                try? FileManager.default.removeItem(at: tempExportURL)
                throw CancellationError()
            }
            let resolvedURL = try await resolveURL()
            if Task.isCancelled {
                if resolvedURL == tempExportURL {
                    try? FileManager.default.removeItem(at: tempExportURL)
                }
                throw CancellationError()
            }
            return resolvedURL
        } catch {
            try? FileManager.default.removeItem(at: tempExportURL)
            throw error
        }
    }
    #else
    public func loadVideoURL(for assetIdentifier: String) async throws -> URL {
        throw NSError(
            domain: "PhotoVideoLoader",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "PhotoKit video loading is unavailable on this platform."]
        )
    }
    #endif

    /// Removes exported temporary videos older than 30 minutes to keep tvOS storage footprint small.
    public func purgeOldExports() {
        let dir = exportDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }

        let now = Date()
        for file in files {
            if let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               now.timeIntervalSince(modified) > 1800 {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
