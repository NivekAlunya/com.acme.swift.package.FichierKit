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
    private var preCancelledSessionIDs: Set<UUID> = []
    private let limiter = SMBVideoThumbnailLimiter(maxConcurrent: 1)

    public init() {}

    /// Extracts a video thumbnail frame using `VLCKit`'s `VLCMediaThumbnailer`.
    ///
    /// - Parameters:
    ///   - url: Local file URL or `SMBStreamingServer` loopback HTTP URL.
    ///   - maxDimension: Maximum pixel bounding box dimension.
    ///   - snapshotPosition: Relative timeline position (`0.0` probes timestamp 0 explicitly).
    ///   - timeoutSeconds: Watchdog timeout ceiling in seconds.
    /// - Returns: Rendered `UIImage` frame, or `nil` on failure, timeout, or cancellation.
    public func generateThumbnail(
        from url: URL,
        maxDimension: CGFloat = 520,
        snapshotPosition: Float = 0.05,
        timeoutSeconds: Double = 6.0,
        snapshotTimeSeconds: Double? = nil
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
                snapshotTimeSeconds: snapshotTimeSeconds
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
        snapshotTimeSeconds: Double?
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        let sessionID = UUID()
        let session = await VLCVideoThumbnailSession(sessionID: sessionID, owner: self)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if self.preCancelledSessionIDs.remove(sessionID) != nil || Task.isCancelled {
                    Task {
                        await session.cancel()
                    }
                    continuation.resume(returning: nil)
                    return
                }

                self.activeSessions[sessionID] = session
                self.pendingRequests[sessionID] = continuation

                Task {
                    await session.start(
                        with: url,
                        maxDimension: maxDimension,
                        snapshotPosition: snapshotPosition,
                        snapshotTimeSeconds: snapshotTimeSeconds
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
        guard let continuation = pendingRequests.removeValue(forKey: id) else {
            preCancelledSessionIDs.insert(id)
            if let session = activeSessions.removeValue(forKey: id) {
                await session.cancel()
            }
            return
        }

        preCancelledSessionIDs.remove(id)
        if let session = activeSessions.removeValue(forKey: id) {
            await session.cancel()
        }
        continuation.resume(returning: image)
    }
    #else
    public init() {}

    public func generateThumbnail(
        from url: URL,
        maxDimension: CGFloat = 520,
        snapshotPosition: Float = 0.05,
        timeoutSeconds: Double = 6.0,
        snapshotTimeSeconds: Double? = nil
    ) async -> Any? {
        nil
    }
    #endif
}
