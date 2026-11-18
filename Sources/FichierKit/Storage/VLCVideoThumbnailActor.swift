//
//  VLCVideoThumbnailActor.swift
//  FichierKit
//
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Actor serializing LibVLC video thumbnail extraction sessions across `tvOS` and `iOS`,
/// enforcing watchdog timeouts and immediate cooperative task cancellation.
public actor VLCVideoThumbnailActor {
    public static let shared = VLCVideoThumbnailActor()

    #if canImport(UIKit)
    private var pendingRequests: [UUID: CheckedContinuation<UIImage?, Never>] = [:]
    private var activeSessions: [UUID: VLCVideoThumbnailSession] = [:]
    private var watchdogTasks: [UUID: Task<Void, Never>] = [:]
    private let limiter = SMBVideoThumbnailLimiter(maxConcurrent: 1)

    public init() {}

    /// Extracts a video thumbnail frame using `VLCKit`'s `VLCMediaThumbnailer`.
    ///
    /// - Parameters:
    ///   - url: Local file URL, network URL, or direct `smb://` URL.
    ///   - maxDimension: Maximum pixel bounding box dimension.
    ///   - snapshotPosition: Relative timeline position (`0.0` probes timestamp 0 explicitly).
    ///   - timeoutSeconds: Watchdog timeout ceiling in seconds.
    ///   - snapshotTimeSeconds: Optional absolute timestamp in seconds to seek to.
    ///   - options: Optional LibVLC media options (e.g. SMB credentials and caching flags).
    /// - Returns: Rendered `UIImage` frame, or `nil` on failure, timeout, or cancellation.
    public func generateThumbnail(
        from url: URL,
        maxDimension: CGFloat = 520,
        snapshotPosition: Float = 0.05,
        timeoutSeconds: Double = 6.0,
        snapshotTimeSeconds: Double? = nil,
        options: VLCPlaybackOptions? = nil
    ) async -> UIImage? {
        #if canImport(VLCKit)
        guard !Task.isCancelled else { return nil }

        return try? await limiter.withPermit {
            guard !Task.isCancelled else { return nil }
            return await self.runSerializedSession(
                url: url,
                maxDimension: maxDimension,
                snapshotPosition: snapshotPosition,
                timeoutSeconds: timeoutSeconds,
                snapshotTimeSeconds: snapshotTimeSeconds,
                options: options
            )
        }
        #else
        return nil
        #endif
    }

    private func runSerializedSession(
        url: URL,
        maxDimension: CGFloat,
        snapshotPosition: Float,
        timeoutSeconds: Double,
        snapshotTimeSeconds: Double?,
        options: VLCPlaybackOptions?
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        let sessionID = UUID()
        let session = await VLCVideoThumbnailSession(sessionID: sessionID, owner: self)
        activeSessions[sessionID] = session

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard self.activeSessions[sessionID] != nil, !Task.isCancelled else {
                    self.activeSessions.removeValue(forKey: sessionID)
                    Task {
                        await session.cancel()
                    }
                    continuation.resume(returning: nil)
                    return
                }

                self.pendingRequests[sessionID] = continuation

                Task {
                    await session.start(
                        with: url,
                        maxDimension: maxDimension,
                        snapshotPosition: snapshotPosition,
                        snapshotTimeSeconds: snapshotTimeSeconds,
                        options: options
                    )
                }

                let watchdog = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeoutSeconds))
                    await self?.cancelSession(id: sessionID, image: nil)
                }
                self.watchdogTasks[sessionID] = watchdog
            }
        } onCancel: {
            Task {
                await self.cancelSession(id: sessionID, image: nil)
            }
        }
    }

    /// Receives extraction result from `VLCVideoThumbnailSession`.
    public func handleSessionCompletion(id: UUID, image: UIImage?) async {
        await cancelSession(id: id, image: image)
    }

    private func cancelSession(id: UUID, image: UIImage?) async {
        watchdogTasks.removeValue(forKey: id)?.cancel()
        guard let session = activeSessions.removeValue(forKey: id) else {
            return
        }

        await session.cancel()
        if let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(returning: image)
        }
    }
    #else
    public init() {}

    public func generateThumbnail(
        from url: URL,
        maxDimension: CGFloat = 520,
        snapshotPosition: Float = 0.05,
        timeoutSeconds: Double = 6.0,
        snapshotTimeSeconds: Double? = nil,
        options: VLCPlaybackOptions? = nil
    ) async -> Any? {
        nil
    }
    #endif
}
