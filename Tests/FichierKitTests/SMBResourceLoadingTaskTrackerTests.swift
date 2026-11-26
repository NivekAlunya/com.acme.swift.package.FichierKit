//
//  SMBResourceLoadingTaskTrackerTests.swift
//  FichierKitTests
//

import Foundation
import Synchronization
import Testing
@testable import FichierKit

@Suite("SMBResourceLoadingTaskTracker Tests")
struct SMBResourceLoadingTaskTrackerTests {
    private final class Token: NSObject, Sendable {}

    @Test("Out-of-order cancelTask before runTask prevents operation from starting")
    func cancelBeforeRunPreventsExecution() async {
        let tracker = SMBResourceLoadingTaskTracker()
        let token = Token()
        let requestID = ObjectIdentifier(token)
        let started = Mutex(false)

        await tracker.cancelTask(for: requestID)
        await tracker.runTask(for: requestID, isCancelled: false) {
            started.withLock { $0 = true }
        }

        try? await Task.sleep(for: .milliseconds(30))
        #expect(started.withLock { $0 } == false)
    }

    @Test("cancelTask cancels an active in-flight task")
    func cancelActiveTaskPropagatesCancellation() async {
        let tracker = SMBResourceLoadingTaskTracker()
        let token = Token()
        let requestID = ObjectIdentifier(token)
        let sawCancellation = Mutex(false)

        await tracker.runTask(for: requestID, isCancelled: false) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
            }
            sawCancellation.withLock { $0 = true }
        }

        try? await Task.sleep(for: .milliseconds(15))
        await tracker.cancelTask(for: requestID)
        try? await Task.sleep(for: .milliseconds(30))

        #expect(sawCancellation.withLock { $0 } == true)
    }

    @Test("cancelAll stops tracker and blocks subsequent runTask calls")
    func cancelAllStopsSubsequentTasks() async {
        let tracker = SMBResourceLoadingTaskTracker()
        let token = Token()
        let requestID = ObjectIdentifier(token)
        let ranAfterStop = Mutex(false)

        await tracker.cancelAll()
        await tracker.runTask(for: requestID, isCancelled: false) {
            ranAfterStop.withLock { $0 = true }
        }

        try? await Task.sleep(for: .milliseconds(30))
        #expect(ranAfterStop.withLock { $0 } == false)
    }
}
