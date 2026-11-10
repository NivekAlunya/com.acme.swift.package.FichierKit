//
//  SharesCursorStoreTests.swift
//  FichierKitTests
//
//

import Foundation
import Testing
@testable import FichierKit

@Suite("SharesCursorStore Tests")
struct SharesCursorStoreTests {
    @Test("Lookup handles initial page, recorded hit, miss fallback, and exhausted scope")
    func testLookupHitMissAndExhaustion() async {
        let store = SharesCursorStore(maxTrackedScopes: 4)
        let scope = "folderA|name|asc|25"

        // Initial page lookup requires no stored cursor and adds no phantom tracked scope
        let initial = await store.cursor(forPage: 0, scopeKey: scope, pageSize: 25)
        #expect(!initial.shouldSkipFetch)
        #expect(initial.cursor == nil)
        #expect(await store.trackedScopeCount == 0)

        // Miss fallback computes deterministic page * pageSize cursor
        let miss = await store.cursor(forPage: 3, scopeKey: "untracked", pageSize: 25)
        #expect(!miss.shouldSkipFetch)
        #expect(miss.cursor == "75")
        #expect(await store.trackedScopeCount == 0)

        // Recording a continuation cursor hits on the following page
        await store.record(nextCursor: "opaque-page-1", afterPage: 0, forScope: scope)
        let hit = await store.cursor(forPage: 1, scopeKey: scope, pageSize: 25)
        #expect(!hit.shouldSkipFetch)
        #expect(hit.cursor == "opaque-page-1")

        // Recording nil marks the scope exhausted only past the recorded final page
        await store.record(nextCursor: nil, afterPage: 1, forScope: scope)
        let replayLastPage = await store.cursor(forPage: 1, scopeKey: scope, pageSize: 25)
        #expect(!replayLastPage.shouldSkipFetch)
        #expect(replayLastPage.cursor == "opaque-page-1")

        let pastEnd = await store.cursor(forPage: 2, scopeKey: scope, pageSize: 25)
        #expect(pastEnd.shouldSkipFetch)
        #expect(pastEnd.cursor == nil)
    }

    @Test("Resetting one scope leaves unrelated scopes intact even when more than 8 scopes exist")
    func testResetScopeIsolationWithoutGlobalPurge() async {
        let store = SharesCursorStore(maxTrackedScopes: 32)
        for index in 0..<12 {
            await store.record(nextCursor: "cursor-\(index)", afterPage: 0, forScope: "scope-\(index)")
        }
        await store.record(nextCursor: nil, afterPage: 1, forScope: "scope-5")

        // Resetting one scope must only clear that scope
        await store.resetScope("scope-3")

        #expect(await !store.isScopeTracked("scope-3"))
        let resetLookup = await store.cursor(forPage: 1, scopeKey: "scope-3", pageSize: 10)
        #expect(!resetLookup.shouldSkipFetch)
        #expect(resetLookup.cursor == "10")

        // Neighboring active and exhausted scopes stay intact
        #expect(await store.trackedScopeCount == 11)
        let intactLookup = await store.cursor(forPage: 1, scopeKey: "scope-0", pageSize: 10)
        #expect(!intactLookup.shouldSkipFetch)
        #expect(intactLookup.cursor == "cursor-0")

        let exhaustedIntact = await store.cursor(forPage: 2, scopeKey: "scope-5", pageSize: 10)
        #expect(exhaustedIntact.shouldSkipFetch)
        #expect(exhaustedIntact.cursor == nil)
    }

    @Test("Bounded LRU evicts only least-recently-used scope and re-access prevents eviction")
    func testBoundedLRUEvictionAndReaccess() async {
        let store = SharesCursorStore(maxTrackedScopes: 2)

        await store.record(nextCursor: "a-next", afterPage: 0, forScope: "A")
        await store.record(nextCursor: "b-next", afterPage: 0, forScope: "B")
        #expect(await store.trackedScopeCount == 2)

        // Re-access A via cursor lookup so B becomes least recently used
        let reaccessedA = await store.cursor(forPage: 1, scopeKey: "A", pageSize: 10)
        #expect(reaccessedA.cursor == "a-next")

        // Inserting C must evict B only, keeping A and C
        await store.record(nextCursor: "c-next", afterPage: 0, forScope: "C")
        #expect(await store.trackedScopeCount == 2)
        #expect(await store.isScopeTracked("A"))
        #expect(await !store.isScopeTracked("B"))
        #expect(await store.isScopeTracked("C"))

        #expect(await store.cursor(forPage: 1, scopeKey: "A", pageSize: 10).cursor == "a-next")
        #expect(await store.cursor(forPage: 1, scopeKey: "C", pageSize: 10).cursor == "c-next")

        // Mark B again as exhausted (`nextCursor: nil`), then evict B via D and E -> LRU order: [C, B] -> [B, D] -> [D, E]
        await store.record(nextCursor: nil, afterPage: 0, forScope: "B")
        await store.record(nextCursor: "d-next", afterPage: 0, forScope: "D")
        await store.record(nextCursor: "e-next", afterPage: 0, forScope: "E")
        #expect(await !store.isScopeTracked("B"))

        let restartedB0 = await store.cursor(forPage: 0, scopeKey: "B", pageSize: 20)
        #expect(!restartedB0.shouldSkipFetch)
        #expect(restartedB0.cursor == nil)

        let restartedB2 = await store.cursor(forPage: 2, scopeKey: "B", pageSize: 20)
        #expect(!restartedB2.shouldSkipFetch)
        #expect(restartedB2.cursor == "40")
    }
}
