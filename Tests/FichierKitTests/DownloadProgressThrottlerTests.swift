//
//  DownloadProgressThrottlerTests.swift
//  FichierKitTests
//

import Foundation
import Testing
@testable import FichierKit

@Suite("DownloadProgressThrottler Tests")
struct DownloadProgressThrottlerTests {

    @Test("Throttles rapid minor progress notifications")
    func testThrottlingMinorDeltas() async {
        let throttler = DownloadProgressThrottler(minimumInterval: .milliseconds(100), minimumPercentDelta: 5)

        // 0 or negative total
        let reportZeroTotal = await throttler.shouldReport(bytes: 10, total: 0)
        #expect(!reportZeroTotal)

        // Initial 1% jump (< 5%)
        let report1 = await throttler.shouldReport(bytes: 10, total: 1000)
        #expect(!report1)

        // Jump to 10% (>= 5%)
        let report10 = await throttler.shouldReport(bytes: 100, total: 1000)
        #expect(report10)

        // Immediate minor step to 11% (1% delta, zero time delta)
        let report11 = await throttler.shouldReport(bytes: 110, total: 1000)
        #expect(!report11)

        // Jump to 20% (>= 5%)
        let report20 = await throttler.shouldReport(bytes: 200, total: 1000)
        #expect(report20)

        // Reaching completion always reports true
        let reportComplete = await throttler.shouldReport(bytes: 1000, total: 1000)
        #expect(reportComplete)
    }

    @Test("Reports when minimum time interval elapses")
    func testTimeIntervalElapsed() async throws {
        let throttler = DownloadProgressThrottler(minimumInterval: .milliseconds(50), minimumPercentDelta: 10)

        // Initial progress at 1%
        let reportInitial = await throttler.shouldReport(bytes: 10, total: 1000)
        #expect(!reportInitial)

        // Wait for interval to elapse
        try await Task.sleep(for: .milliseconds(60))

        // Even with minor delta (2%), time elapsed triggers report
        let reportAfterTime = await throttler.shouldReport(bytes: 20, total: 1000)
        #expect(reportAfterTime)
    }
}
