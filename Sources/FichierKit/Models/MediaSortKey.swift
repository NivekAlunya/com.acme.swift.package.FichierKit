//
//  MediaSortKey.swift
//  FichierKit
//

import Foundation

/// Attributes by which a media source can sort its contents.
public enum MediaSortKey: String, Sendable, CaseIterable, Identifiable, Codable {
    case name
    case date
    case size
    case type

    public var id: String { rawValue }

    /// Human-readable display title shown in browser sort controls and menus.
    public var displayTitle: String {
        switch self {
        case .name:
            return "Filename"
        case .date:
            return "Date"
        case .size:
            return "Size"
        case .type:
            return "Type"
        }
    }
}
