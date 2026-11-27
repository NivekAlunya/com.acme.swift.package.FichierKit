//
//  PhotoSubtype.swift
//  FichierKit
//
//

import Foundation

/// Classifies specialized photo formats and capture modes across PhotoKit and file-based sources.
public enum PhotoSubtype: String, Sendable, Hashable, Equatable, CaseIterable {
    case standard
    case raw
    case livePhoto
    case animated
    case hdr
    case panorama
    case portrait
    case screenshot

    /// Known camera RAW file extensions (lowercase, without leading dot).
    private static let rawExtensions: Set<String> = [
        "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "pef", "raf", "raw"
    ]

    /// Known animated raster image file extensions (lowercase, without leading dot).
    private static let animatedExtensions: Set<String> = [
        "gif", "webp", "avif"
    ]

    /// Infers a `PhotoSubtype` from a file extension when PhotoKit metadata is unavailable.
    public static func from(extension ext: String) -> PhotoSubtype {
        let cleaned = ext.trimmingCharacters(in: CharacterSet(charactersIn: ". \t\r\n")).lowercased()
        if rawExtensions.contains(cleaned) {
            return .raw
        }
        if animatedExtensions.contains(cleaned) {
            return .animated
        }
        return .standard
    }

    /// Short uppercase badge label for specialized subtypes, or `nil` for standard photos.
    public var badgeLabel: String? {
        switch self {
        case .standard: return nil
        case .raw: return "RAW"
        case .livePhoto: return "LIVE"
        case .animated: return "GIF"
        case .hdr: return "HDR"
        case .panorama: return "PANO"
        case .portrait: return "PORTRAIT"
        case .screenshot: return "SCREEN"
        }
    }

    /// SF Symbol name representing this photo subtype.
    public var badgeSymbolName: String {
        switch self {
        case .standard: return "photo.fill"
        case .raw: return "camera.aperture"
        case .livePhoto: return "livephoto"
        case .animated: return "play.square.stack"
        case .hdr: return "hdr"
        case .panorama: return "pano"
        case .portrait: return "person.crop.rectangle"
        case .screenshot: return "camera.viewfinder"
        }
    }
}
