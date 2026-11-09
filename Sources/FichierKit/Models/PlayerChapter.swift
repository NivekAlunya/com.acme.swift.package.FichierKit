//
//  PlayerChapter.swift
//  FichierKit
//
//

import Foundation

/// Represents an embedded chapter marker within a video stream.
public struct PlayerChapter: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let startTime: Double
    public let duration: Double

    public init(id: String, title: String, startTime: Double, duration: Double) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.duration = duration
    }
}
