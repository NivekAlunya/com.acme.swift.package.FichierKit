//
//  ThumbnailPrefetchCoordinator.swift
//  FichierKit
//
//

import Foundation

/// `@MainActor` gate that pauses uncached visible thumbnail generation while a scroll view is
/// actively scrolling, resuming immediately when scrolling reaches `.idle`.
@MainActor
public final class ThumbnailPrefetchCoordinator {
    public static let shared = ThumbnailPrefetchCoordinator()

    private var isScrolling: Bool = false
    private var scrollIdleWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    public init() {}

    /// Updates scroll activity state synchronously on `@MainActor`; when scrolling stops,
    /// immediately resumes any waiting visible thumbnail loads.
    public func setScrolling(_ scrolling: Bool) {
        guard isScrolling != scrolling else { return }
        isScrolling = scrolling
        if !scrolling {
            let waiters = Array(scrollIdleWaiters.values)
            scrollIdleWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    /// Suspends while the user is actively scrolling so fast-scrolled cells don't saturate SMB sockets.
    /// Returns immediately if scroll is already idle or the task is cancelled.
    public func waitUntilScrollIdle() async {
        while isScrolling && !Task.isCancelled {
            let waiterID = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if !isScrolling || Task.isCancelled {
                        continuation.resume()
                    } else {
                        scrollIdleWaiters[waiterID] = continuation
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    if let waiter = self?.scrollIdleWaiters.removeValue(forKey: waiterID) {
                        waiter.resume()
                    }
                }
            }
        }
    }
}
