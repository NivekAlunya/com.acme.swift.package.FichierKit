//
//  ThumbnailPrefetchCoordinatorTests.swift
//  FichierKitTests
//
//

import Foundation
import Testing
@testable import FichierKit

@Suite("ThumbnailPrefetchCoordinator")
struct ThumbnailPrefetchCoordinatorTests {

    @Test("Gates visible loads while scrolling and resumes when idle")
    @MainActor
    func gatesBehindScrolling() async {
        let coordinator = ThumbnailPrefetchCoordinator()
        var completed = false

        coordinator.setScrolling(true)
        let waiter = Task { @MainActor in
            await coordinator.waitUntilScrollIdle()
            completed = true
        }

        try? await Task.sleep(for: .milliseconds(50))
        #expect(completed == false)

        coordinator.setScrolling(false)
        await waiter.value
        #expect(completed == true)
    }

    @Test("Cancelled waiter resumes immediately without waiting for scroll idle")
    @MainActor
    func cancelledWaiterResumesImmediately() async {
        let coordinator = ThumbnailPrefetchCoordinator()
        coordinator.setScrolling(true)

        let waiter = Task { @MainActor in
            await coordinator.waitUntilScrollIdle()
        }

        try? await Task.sleep(for: .milliseconds(20))
        waiter.cancel()
        await waiter.value
        #expect(waiter.isCancelled == true)
    }

    @Test("Clearing one scroll source does not resume while another source is scrolling")
    @MainActor
    func perSourceIsolation() async {
        let coordinator = ThumbnailPrefetchCoordinator()
        let sourceA = UUID()
        let sourceB = UUID()
        var completed = false

        coordinator.setScrolling(true, sourceID: sourceA)
        coordinator.setScrolling(true, sourceID: sourceB)

        let waiter = Task { @MainActor in
            await coordinator.waitUntilScrollIdle()
            completed = true
        }

        try? await Task.sleep(for: .milliseconds(30))
        coordinator.setScrolling(false, sourceID: sourceA)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(completed == false)

        coordinator.setScrolling(false, sourceID: sourceB)
        await waiter.value
        #expect(completed == true)
    }
}
