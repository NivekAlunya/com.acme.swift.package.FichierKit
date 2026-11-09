//
//  SMBResourceLoadingTaskTracker.swift
//  FichierKit
//
//

import Foundation
import AVFoundation

/// Actor coordinating asynchronous tasks spawned by `SMBAVAssetResourceLoaderDelegate`.
///
/// Tracks active `AVAssetResourceLoadingRequest` tasks by object identity and caches out-of-order
/// cancellation notices in a bounded LRU queue so cancelled requests never spawn orphan SMB reads.
actor SMBResourceLoadingTaskTracker {
    private var activeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var cancelledRequests: Set<ObjectIdentifier> = []
    private var cancelledOrder: [ObjectIdentifier] = []
    private let maxCancelledCapacity = 64
    private var isStopped = false

    func runTask(
        for requestID: ObjectIdentifier,
        isCancelled: Bool,
        operation: @Sendable @escaping () async -> Void
    ) {
        if isStopped {
            return
        }
        if cancelledRequests.remove(requestID) != nil {
            cancelledOrder.removeAll { $0 == requestID }
            return
        }
        guard !isCancelled else { return }

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            await operation()
            await self?.remove(for: requestID)
        }
        activeTasks[requestID] = task
    }

    func remove(for requestID: ObjectIdentifier) {
        activeTasks.removeValue(forKey: requestID)
        if cancelledRequests.remove(requestID) != nil {
            cancelledOrder.removeAll { $0 == requestID }
        }
    }

    func cancelTask(for requestID: ObjectIdentifier) {
        if let task = activeTasks.removeValue(forKey: requestID) {
            task.cancel()
        } else if !isStopped {
            let (inserted, _) = cancelledRequests.insert(requestID)
            if inserted {
                cancelledOrder.append(requestID)
                if cancelledOrder.count > maxCancelledCapacity {
                    let oldest = cancelledOrder.removeFirst()
                    cancelledRequests.remove(oldest)
                }
            }
        }
    }

    func cancelAll() {
        isStopped = true
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        cancelledRequests.removeAll()
        cancelledOrder.removeAll()
        tasks.forEach { $0.cancel() }
    }
}
