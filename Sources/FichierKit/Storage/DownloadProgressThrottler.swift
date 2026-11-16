//
//  DownloadProgressThrottler.swift
//  FichierKit
//

import Foundation

/// Pure Swift Concurrency rate limiter for progress reporting.
/// Ensures UI updates and heavy string formatting occur at most once per minimum time interval or percentage step.
public actor DownloadProgressThrottler {
    private var lastReportedPercent: Int = 0
    private var lastReportedTime: ContinuousClock.Instant = .now
    private let minimumInterval: Duration
    private let minimumPercentDelta: Int

    /// Initializes a progress throttler with the specified rate limits.
    /// - Parameters:
    ///   - minimumInterval: The minimum time between successive notifications (default 100ms).
    ///   - minimumPercentDelta: The minimum integer percent increase between notifications (default 1%).
    public init(
        minimumInterval: Duration = .milliseconds(100),
        minimumPercentDelta: Int = 1
    ) {
        self.minimumInterval = minimumInterval
        self.minimumPercentDelta = minimumPercentDelta
    }

    /// Determines if a progress notification should be dispatched based on time or percent change.
    /// Always returns `true` upon completion (`bytes >= total`).
    /// - Parameters:
    ///   - bytes: Number of bytes currently transferred.
    ///   - total: Total number of bytes expected.
    /// - Returns: `true` if the caller should report progress; otherwise `false`.
    public func shouldReport(bytes: Int64, total: Int64) -> Bool {
        guard total > 0 else { return false }
        if bytes >= total {
            lastReportedPercent = 100
            lastReportedTime = ContinuousClock.now
            return true
        }
        let percent = Int(Double(bytes) / Double(total) * 100)
        let now = ContinuousClock.now
        if percent - lastReportedPercent >= minimumPercentDelta || now - lastReportedTime >= minimumInterval {
            lastReportedPercent = percent
            lastReportedTime = now
            return true
        }
        return false
    }
}
