//
//  PlayerSubtitleTrack.swift
//  FichierKit
//

import Foundation

/// Describes a subtitle or closed caption option.
public struct PlayerSubtitleTrack: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let languageCode: String?

    public init(id: String, title: String, languageCode: String? = nil) {
        self.id = id
        self.title = title
        self.languageCode = languageCode
    }
}
