//
//  SMBVideoThumbnailLimiter.swift
//  FichierKit
//
//

import Foundation

/// Actor-based FIFO concurrency limiter regulating video thumbnail extraction tasks.
///
/// Caps simultaneous video probes to avoid congesting a single SMB TCP socket or overloading
/// hardware video decoders when browsing dense folders on tvOS.
public actor SMBVideoThumbnailLimiter {
    private var activeCount: Int = 0
    private let maxConcurrent: Int
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    /// Initializes the limiter with a maximum concurrent permit count (minimum 1).
    public init(maxConcurrent: Int = 2) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// Executes an operation once a concurrency permit is granted, honoring cooperative cancellation.
    public func withPermit<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        let waiterID = UUID()
        let acquired = await withTaskCancellationHandler {
            await acquire(id: waiterID)
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterID)
            }
        }

        guard acquired, !Task.isCancelled else {
            if acquired {
                release()
            }
            throw CancellationError()
        }

        defer {
            release()
        }

        return try await operation()
    }

    private func acquire(id: UUID) async -> Bool {
        if Task.isCancelled {
            return false
        }
        if activeCount < maxConcurrent {
            activeCount += 1
            return true
        }
        return await withCheckedContinuation { continuation in
            if Task.isCancelled {
                continuation.resume(returning: false)
                return
            }
            waiters.append((id: id, continuation: continuation))
        }
    }

    private func cancelWaiter(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        }
    }

    private func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.continuation.resume(returning: true)
        } else {
            activeCount = max(0, activeCount - 1)
        }
    }
}
