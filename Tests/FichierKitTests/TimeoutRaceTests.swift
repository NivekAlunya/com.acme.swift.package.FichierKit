//
//  TimeoutRaceTests.swift
//  FichierKitTests
//

import Foundation
import Synchronization
import Testing
@testable import FichierKit

@Suite("Timeout Race Cancellation Tests")
struct TimeoutRaceTests {
    @Test("onAbort does not fire when operation wins the race before timeout")
    func onAbortNotCalledWhenOperationSucceeds() async {
        let abortCalled = Mutex(false)

        let result: Int? = await SMBVideoThumbnailLoader.raceWithTimeout(
            timeoutSeconds: 0.15,
            onAbort: { abortCalled.withLock { $0 = true } }
        ) {
            42
        }

        try? await Task.sleep(for: .milliseconds(200))
        #expect(result == 42)
        #expect(abortCalled.withLock { $0 } == false)
    }

    @Test("onAbort fires when operation stalls past timeout")
    func onAbortCalledOnTimeout() async {
        let abortCalled = Mutex(false)

        let result: Int? = await SMBVideoThumbnailLoader.raceWithTimeout(
            timeoutSeconds: 0.03,
            onAbort: { abortCalled.withLock { $0 = true } }
        ) {
            try? await Task.sleep(for: .seconds(1))
            return 42
        }

        #expect(result == nil)
        #expect(abortCalled.withLock { $0 } == true)
    }
}
