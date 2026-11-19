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

    /// Resolves the media item type from a file extension, or returns `nil` if unsupported.
    public static func from(extension ext: String) -> MediaItemType? {
        let cleanExt = ext.trimmingCharacters(in: CharacterSet(charactersIn: ". \t\r\n")).lowercased()
        guard SupportedMediaTypes.isSupported(extension: cleanExt) else {
            return nil
        }
        if SupportedMediaTypes.isVideo(extension: cleanExt) {
            return .video
        }
        #if !os(tvOS)
        if SupportedMediaTypes.isDocument(extension: cleanExt) {
            return .document
        }
        #endif
        return .image
    }
}
