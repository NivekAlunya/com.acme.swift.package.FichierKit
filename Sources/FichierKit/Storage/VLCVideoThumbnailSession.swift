//
//  VLCVideoThumbnailSession.swift
//  FichierKit
//
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(VLCKit)
import VLCKit
#endif

#if canImport(UIKit)
/// `@MainActor` Objective-C delegate bridge driving a single `VLCMediaThumbnailer` extraction
/// and hopping its result back to `VLCVideoThumbnailActor`.
@MainActor
public final class VLCVideoThumbnailSession: NSObject {
    private let sessionID: UUID
    private weak var owner: VLCVideoThumbnailActor?

    #if canImport(VLCKit)
    private var thumbnailer: VLCMediaThumbnailer?
    #endif
    private var didComplete: Bool = false

    public init(sessionID: UUID, owner: VLCVideoThumbnailActor) {
        self.sessionID = sessionID
        self.owner = owner
        super.init()
    }

    /// Starts asynchronous thumbnail generation for the given file, network or direct `smb://` URL.
    public func start(
        with url: URL,
        maxDimension: CGFloat,
        snapshotPosition: Float,
        snapshotTimeSeconds: Double? = nil,
        options: VLCPlaybackOptions? = nil
    ) {
        guard !didComplete else { return }

        #if canImport(VLCKit)
        guard let media = VLCMedia(url: url) else {
            notifyCompletion(image: nil)
            return
        }

        if let mediaOptions = options?.makeVLCMediaOptionsDictionary(for: url) {
            media.addOptions(mediaOptions)
        }

        let thumb = VLCMediaThumbnailer(media: media, andDelegate: self)
        thumb.thumbnailWidth = maxDimension
        thumb.thumbnailHeight = maxDimension
        thumb.cropsToFit = false
        thumb.preciseSeek = false

        if let snapshotTimeSeconds, snapshotTimeSeconds.isFinite, !snapshotTimeSeconds.isNaN {
            if snapshotTimeSeconds <= 0.05 {
                thumb.snapshotTime = VLCTime(int: 0)
            } else {
                let targetMs = Int32(clamping: Int64(snapshotTimeSeconds * 1000.0))
                thumb.snapshotTime = VLCTime(int: targetMs)
            }
        } else if snapshotPosition <= 0 {
            // Explicit t=0 avoids LibVLC's default 0.3 position fallback when snapshotPosition == 0.
            thumb.snapshotTime = VLCTime(int: 0)
        } else {
            thumb.snapshotPosition = min(0.95, max(0.01, snapshotPosition))
        }

        self.thumbnailer = thumb
        thumb.fetchThumbnail()
        #else
        notifyCompletion(image: nil)
        #endif
    }

    /// Cancels any active VLC thumbnailer task and releases references immediately.
    public func cancel() {
        didComplete = true
        #if canImport(VLCKit)
        thumbnailer?.cancel()
        thumbnailer = nil
        #endif
        owner = nil
    }

    private func notifyCompletion(image: UIImage?) {
        guard !didComplete else { return }
        didComplete = true

        let id = sessionID
        let currentOwner = owner
        owner = nil
        #if canImport(VLCKit)
        thumbnailer = nil
        #endif

        Task {
            await currentOwner?.handleSessionCompletion(id: id, image: image)
        }
    }
}

#if canImport(VLCKit)
extension VLCVideoThumbnailSession: VLCMediaThumbnailerDelegate {
    public nonisolated func mediaThumbnailer(
        _ mediaThumbnailer: VLCMediaThumbnailer,
        didFinishThumbnail thumbnail: CGImage
    ) {
        let image = UIImage(cgImage: thumbnail)
        Task { @MainActor [weak self] in
            self?.notifyCompletion(image: image)
        }
    }

    public nonisolated func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
        Task { @MainActor [weak self] in
            self?.notifyCompletion(image: nil)
        }
    }
}
#endif
#endif
