//
//  SharesCursorStore.swift
//  FichierKit
//
//

import Foundation

/// Actor isolating page-to-cursor mappings so sequential `MediaSource.fetchItems` calls avoid full re-enumeration.
actor SharesCursorStore {
    private var cursorsByScope: [String: [Int: String]] = [:]
    private var exhaustedScopes: Set<String> = []
    private var maxTrackedPageByScope: [String: Int] = [:]

    func resetScope(_ scopeKey: String) {
        if cursorsByScope.count > 8 {
            cursorsByScope.removeAll()
            exhaustedScopes.removeAll()
            maxTrackedPageByScope.removeAll()
        } else {
            cursorsByScope.removeValue(forKey: scopeKey)
            exhaustedScopes.remove(scopeKey)
            maxTrackedPageByScope.removeValue(forKey: scopeKey)
        }
    }

    func cursor(forPage page: Int, scopeKey: String, pageSize: Int) -> (shouldSkipFetch: Bool, cursor: String?) {
        if page <= 0 {
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
        maxTrackedPageByScope[scopeKey] = max(maxTrackedPageByScope[scopeKey] ?? 0, page)
        if let nextCursor {
            exhaustedScopes.remove(scopeKey)
            cursorsByScope[scopeKey, default: [:]][page + 1] = nextCursor
        } else {
            cursorsByScope[scopeKey]?.removeValue(forKey: page + 1)
            exhaustedScopes.insert(scopeKey)
        }
    }
}
