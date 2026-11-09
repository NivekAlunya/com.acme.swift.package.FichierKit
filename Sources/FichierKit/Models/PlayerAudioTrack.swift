//
//  PlayerAudioTrack.swift
//  FichierKit
//

import Foundation

/// Describes an available audio stream within a playing video.
public struct PlayerAudioTrack: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let languageCode: String?

    public init(id: String, title: String, languageCode: String? = nil) {
        self.id = id
        self.title = title
        self.languageCode = languageCode
    }
}
