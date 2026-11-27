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

    private static let defaultSourceID = UUID()

    private var activeScrollSources: Set<UUID> = []
    private var scrollIdleWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    private var isScrolling: Bool { !activeScrollSources.isEmpty }

    public init() {}

    /// Updates scroll activity state for a specific view source synchronously on `@MainActor`.
    /// When no active scrolling sources remain, immediately resumes any waiting visible thumbnail loads.
    public func setScrolling(_ scrolling: Bool, sourceID: UUID? = nil) {
        let id = sourceID ?? Self.defaultSourceID
        let wasScrolling = isScrolling
        if scrolling {
            activeScrollSources.insert(id)
        } else {
            activeScrollSources.remove(id)
        }
        if wasScrolling && !isScrolling {
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
