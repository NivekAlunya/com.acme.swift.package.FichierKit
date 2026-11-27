//
//  ThumbnailPrefetchCoordinator.swift
//  FichierKit
//
//

import Foundation

/// Coordinates low-priority background thumbnail generation for offscreen items once visible cells settle.
///
/// Visible thumbnail loads take strict priority via `beginVisibleLoad(isFastMedia:)` / `endVisibleLoad(isFastMedia:)`:
/// - Fast visible media (photos & PDFs) run immediately and preempt any in-flight background prefetch.
/// - Visible videos wait until fast visible media finishes so they don't saturate single-permit SMB sockets.
/// - Background offscreen prefetching waits until all visible loads settle and continues across video playback.
public actor ThumbnailPrefetchCoordinator {
    public static let shared = ThumbnailPrefetchCoordinator()

    private var activeFastVisibleCount: Int = 0
    private var activeSlowVisibleCount: Int = 0
    private var fastIdleWaiters: [CheckedContinuation<Void, Never>] = []
    private var allIdleWaiters: [CheckedContinuation<Void, Never>] = []
    private var activeFolderKey: String?
    private var prefetchTask: Task<Void, Never>?
    private var currentItemTask: Task<Void, Never>?

    public init() {}

    /// Suspends until all currently visible fast media (photos & PDFs) have finished loading.
    public func waitUntilFastVisibleIdle() async {
        while activeFastVisibleCount > 0 && !Task.isCancelled {
            await withCheckedContinuation { continuation in
                if activeFastVisibleCount == 0 || Task.isCancelled {
                    continuation.resume()
                } else {
                    fastIdleWaiters.append(continuation)
                }
            }
        }
    }

    /// Marks the start of a visible cell thumbnail load, pausing background prefetching
    /// and preempting any in-flight background item so visible cells never wait on it.
    public func beginVisibleLoad(isFastMedia: Bool = true) {
        if isFastMedia {
            activeFastVisibleCount += 1
        } else {
            activeSlowVisibleCount += 1
        }
        currentItemTask?.cancel()
    }

    /// Marks the completion or cancellation of a visible cell thumbnail load.
    public func endVisibleLoad(isFastMedia: Bool = true) {
        if isFastMedia {
            if activeFastVisibleCount > 0 {
                activeFastVisibleCount -= 1
            }
            if activeFastVisibleCount == 0 {
                let waiters = fastIdleWaiters
                fastIdleWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume()
                }
            }
        } else if activeSlowVisibleCount > 0 {
            activeSlowVisibleCount -= 1
        }

        if activeFastVisibleCount == 0 && activeSlowVisibleCount == 0 {
            let waiters = allIdleWaiters
            allIdleWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    /// Schedules background prefetching for `items` in `folderKey` at `.utility` priority.
    ///
    /// Images and documents are prefetched before videos. Existing work for a different folder is cancelled.
    public func schedulePrefetch(
        folderKey: String,
        items: [MediaSourceItem],
        loader: @escaping @Sendable (MediaSourceItem) async -> Void
    ) {
        prefetchTask?.cancel()
        currentItemTask?.cancel()
        currentItemTask = nil
        activeFolderKey = folderKey

        let orderedItems = Self.prioritizedItems(from: items)
        guard !orderedItems.isEmpty else {
            prefetchTask = nil
            return
        }

        prefetchTask = Task(priority: .utility) {
            var index = 0
            while index < orderedItems.count {
                guard !Task.isCancelled else { return }
                await self.waitUntilVisibleIdle()
                guard !Task.isCancelled else { return }

                let item = orderedItems[index]
                let wasPreempted = await self.runItemPrefetch(item: item, loader: loader)
                if !wasPreempted {
                    index += 1
                }
            }
        }
    }

    /// Cancels any active background prefetch task.
    public func cancelAll() {
        prefetchTask?.cancel()
        prefetchTask = nil
        currentItemTask?.cancel()
        currentItemTask = nil
        activeFolderKey = nil
    }

    // MARK: - Private Helpers

    private func runItemPrefetch(
        item: MediaSourceItem,
        loader: @escaping @Sendable (MediaSourceItem) async -> Void
    ) async -> Bool {
        let task = Task(priority: .utility) {
            await loader(item)
        }
        currentItemTask = task
        await task.value
        let wasPreempted = task.isCancelled && !Task.isCancelled
        if currentItemTask == task {
            currentItemTask = nil
        }
        return wasPreempted
    }

    private func waitUntilVisibleIdle() async {
        while (activeFastVisibleCount > 0 || activeSlowVisibleCount > 0) && !Task.isCancelled {
            await withCheckedContinuation { continuation in
                if (activeFastVisibleCount == 0 && activeSlowVisibleCount == 0) || Task.isCancelled {
                    continuation.resume()
                } else {
                    allIdleWaiters.append(continuation)
                }
            }
        }
    }

    private nonisolated static func prioritizedItems(from items: [MediaSourceItem]) -> [MediaSourceItem] {
        let nonFolders = items.filter { $0.type != .folder }
        let nonVideos = nonFolders.filter { $0.type != .video }
        let videos = nonFolders.filter { $0.type == .video }
        return nonVideos + videos
    }
}
