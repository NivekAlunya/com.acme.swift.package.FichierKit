//
//  VLCPictureInPictureMediaController.swift
//  FichierKit
//
//  Bridges `VLCMediaPlayer` playback controls and metadata to `VLCPictureInPictureMediaControlling`.
//

import Foundation
#if canImport(VLCKit) && canImport(UIKit) && !os(watchOS)
import VLCKit

/// Adapter bridging `VLCMediaPlayer` playback state and commands to VLCKit's Picture-in-Picture controller.
///
/// Isolated to `@MainActor` because `VLCMediaPlayer` is main-thread-affine and `mediaPlayer` is mutable.
@MainActor
public final class VLCPictureInPictureMediaController: NSObject, @preconcurrency VLCPictureInPictureMediaControlling {
    /// Active `VLCMediaPlayer` instance, or `nil` when detached.
    public weak var mediaPlayer: VLCMediaPlayer?

    /// Creates a media controller bound to the given `VLCMediaPlayer`.
    ///
    /// - Parameter mediaPlayer: Active `VLCMediaPlayer` instance, or `nil` when detached.
    public init(mediaPlayer: VLCMediaPlayer? = nil) {
        self.mediaPlayer = mediaPlayer
        super.init()
    }

    public func play() {
        mediaPlayer?.play()
    }

    public func pause() {
        mediaPlayer?.pause()
    }

    public func seek(by offset: Int64, completion: (() -> Void)!) {
        guard let mediaPlayer else {
            completion?()
            return
        }
        // VLCKit only exposes an Int32 millisecond offset API with completion; Int32.max (~24.8 days) exceeds media lengths.
        let clampedOffset = Int32(clamping: offset)
        let started = mediaPlayer.jump(withOffset: clampedOffset, completion: completion)
        if !started {
            completion?()
        }
    }

    public func mediaLength() -> Int64 {
        mediaPlayer?.media?.length.value?.int64Value ?? 0
    }

    public func mediaTime() -> Int64 {
        mediaPlayer?.time.value?.int64Value ?? 0
    }

    public func isMediaSeekable() -> Bool {
        mediaPlayer?.isSeekable ?? false
    }

    public func isMediaPlaying() -> Bool {
        mediaPlayer?.isPlaying ?? false
    }
}
#endif
