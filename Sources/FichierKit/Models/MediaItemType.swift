//
//  MediaItemType.swift
//  FichierKit
//

import Foundation

/// Defines the category of media represented by an item.
public enum MediaItemType: Sendable, Hashable, Equatable {
    case folder
    case image
    case video
    #if !os(tvOS)
    case document
    #endif
}
