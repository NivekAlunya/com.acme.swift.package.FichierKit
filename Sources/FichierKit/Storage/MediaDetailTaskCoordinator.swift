//
//  MediaDetailTaskCoordinator.swift
//  FichierKit
//
//  Created by Kevin Launay on 19/11/2026.
//

import Foundation

/// Coordinates in-flight media detail resolution tasks and tracks subscriber counts
/// to deduplicate concurrent requests and prevent premature task cancellation.
actor MediaDetailTaskCoordinator {
    /// In-flight resolution record tracking the underlying task and subscriber count.
    private var inFlight: [String: (task: Task<String?, Never>, subscribers: Int)] = [:]

    init() {}

    /// Returns an existing in-flight task incrementing its subscriber count,
    /// or starts a new task with the provided operation.
    func task(
        for key: String,
        operation: @Sendable @escaping () async -> String?
    ) -> Task<String?, Never> {
        if let existing = inFlight[key] {
            inFlight[key] = (task: existing.task, subscribers: existing.subscribers + 1)
            return existing.task
        }

        let newTask = Task<String?, Never> {
            await operation()
        }
        inFlight[key] = (task: newTask, subscribers: 1)
        return newTask
    }

    /// Decrements the subscriber count for a task. Cancels and removes the task
    /// only when no active subscribers remain.
    func cancelSubscriber(for key: String) {
        guard let existing = inFlight[key] else { return }
        let remaining = existing.subscribers - 1
        if remaining <= 0 {
            existing.task.cancel()
            inFlight.removeValue(forKey: key)
        } else {
            inFlight[key] = (task: existing.task, subscribers: remaining)
        }
    }

    /// Cleans up an in-flight entry upon task completion.
    func finish(for key: String) {
        inFlight.removeValue(forKey: key)
    }
}
