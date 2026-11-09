//
//  MediaSourceLayout.swift
//  FichierKit
//

import Foundation

/// Preferred or user-selected visual arrangement for a source's items on tvOS.
public enum MediaSourceLayout: String, Codable, CaseIterable, Sendable, Hashable, Equatable {
    case grid
    case list

    /// Returns the alternate layout mode (`grid` <-> `list`).
    public var toggled: MediaSourceLayout {
        self == .grid ? .list : .grid
    }
}
