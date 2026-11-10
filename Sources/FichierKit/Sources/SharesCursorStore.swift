//
//  SharesCursorStore.swift
//  FichierKit
//
//

import Foundation

/// Actor isolating page-to-cursor mappings so sequential `MediaSource.fetchItems` calls avoid full re-enumeration.
///
/// Scoped to a single `SharesMediaSource` instance; enforces bounded LRU eviction across active scopes
/// (defaulting to `defaultMaxTrackedScopes`) so unrelated active folders are never purged globally.
actor SharesCursorStore {
    /// Default maximum number of `(folder, sortKey, sortOrder, pageSize)` scopes retained concurrently.
    static let defaultMaxTrackedScopes = 64

    private let maxTrackedScopes: Int
    private var cursorsByScope: [String: [Int: String]] = [:]
    private var exhaustedScopes: Set<String> = []
    private var maxTrackedPageByScope: [String: Int] = [:]
    private var accessOrder: [String] = []

    init(maxTrackedScopes: Int = SharesCursorStore.defaultMaxTrackedScopes) {
        self.maxTrackedScopes = max(1, maxTrackedScopes)
    }

    var trackedScopeCount: Int {
        accessOrder.count
    }

    func isScopeTracked(_ scopeKey: String) -> Bool {
        accessOrder.contains(scopeKey)
    }

    func resetScope(_ scopeKey: String) {
        removeScopeMetadata(scopeKey)
    }

    func cursor(forPage page: Int, scopeKey: String, pageSize: Int) -> (shouldSkipFetch: Bool, cursor: String?) {
        if isScopeTracked(scopeKey) {
            touchTrackedScope(scopeKey)
        }
        if page <= 0 {
            return (false, nil)
        }
        guard pageSize > 0 else {
            return (false, nil)
        }
        if let recorded = cursorsByScope[scopeKey]?[page] {
            return (false, recorded)
        }
        if exhaustedScopes.contains(scopeKey),
           let maxPage = maxTrackedPageByScope[scopeKey],
           page > maxPage {
            return (true, nil)
        }
        return (false, String(page * pageSize))
    }

    func record(nextCursor: String?, afterPage page: Int, forScope scopeKey: String) {
        guard page >= 0 else { return }
        touchTrackedScope(scopeKey)
        maxTrackedPageByScope[scopeKey] = max(maxTrackedPageByScope[scopeKey] ?? 0, page)
        if let nextCursor {
            exhaustedScopes.remove(scopeKey)
            cursorsByScope[scopeKey, default: [:]][page + 1] = nextCursor
        } else {
            cursorsByScope[scopeKey]?.removeValue(forKey: page + 1)
            exhaustedScopes.insert(scopeKey)
        }
        evictLeastRecentlyUsedIfNeeded(protecting: scopeKey)
    }

    private func touchTrackedScope(_ scopeKey: String) {
        if let existingIndex = accessOrder.firstIndex(of: scopeKey) {
            accessOrder.remove(at: existingIndex)
        }
        accessOrder.append(scopeKey)
    }

    private func removeScopeMetadata(_ scopeKey: String) {
        cursorsByScope.removeValue(forKey: scopeKey)
        exhaustedScopes.remove(scopeKey)
        maxTrackedPageByScope.removeValue(forKey: scopeKey)
        if let existingIndex = accessOrder.firstIndex(of: scopeKey) {
            accessOrder.remove(at: existingIndex)
        }
    }

    private func evictLeastRecentlyUsedIfNeeded(protecting protectedScopeKey: String) {
        while accessOrder.count > maxTrackedScopes {
            guard let victimIndex = accessOrder.firstIndex(where: { $0 != protectedScopeKey }) else {
                break
            }
            let victimKey = accessOrder[victimIndex]
            removeScopeMetadata(victimKey)
        }
    }
}
