//
//  MediaFormatStyle.swift
//  FichierKit
//
//  Created by Kevin Launay on 19/11/2026.
//

import SwiftUI

/// Visual styling, format labels, and accent colors for media items and file extensions.
public enum MediaFormatStyle: Sendable {

    /// Resolves format badge label, accent color, and SF Symbol pictogram name for arbitrary media attributes.
    public static func formatInfo(
        name: String,
        type: MediaItemType,
        isPDF: Bool = false,
        isGIF: Bool = false,
        photoSubtype: PhotoSubtype? = nil,
        folderCount: Int = 0
    ) -> (label: String, color: Color, pictogramName: String) {
        if type == .folder {
            let label = folderCount > 0 ? "\(folderCount)" : "FOLDER"
            return (label: label, color: Color(white: 0.35), pictogramName: "folder.fill")
        }
        if isPDF {
            return ("PDF", Color(red: 0.90, green: 0.25, blue: 0.25), "doc.text.fill")
        }
        if isGIF {
            return ("GIF", Color.orange, PhotoSubtype.animated.badgeSymbolName)
        }

        let rawExt = (name as NSString).pathExtension.trimmingCharacters(in: .punctuationCharacters)
        let lowerExt = rawExt.lowercased()

        if type == .video {
            let label = rawExt.isEmpty ? "VIDEO" : rawExt.uppercased()
            let color = videoColor(forExtension: lowerExt)
            return (label, color, "play.fill")
        }

        let resolvedSubtype = photoSubtype ?? PhotoSubtype.from(extension: lowerExt)
        let label = resolvedSubtype.badgeLabel ?? (rawExt.isEmpty ? "PHOTO" : rawExt.uppercased())
        let color = photoColor(forExtension: lowerExt, subtype: resolvedSubtype)
        return (label, color, resolvedSubtype.badgeSymbolName)
    }

    /// Resolves format badge label, accent color, and SF Symbol pictogram name for a `MediaSourceItem`.
    public static func formatInfo(for item: MediaSourceItem) -> (label: String, color: Color, pictogramName: String) {
        let ext = (item.name as NSString).pathExtension.lowercased()
        let isPDF = ext == "pdf"
        let isGIF = ext == "gif"
        return formatInfo(
            name: item.name,
            type: item.type,
            isPDF: isPDF,
            isGIF: isGIF,
            photoSubtype: item.photoSubtype,
            folderCount: item.size > 0 ? Int(item.size) : 0
        )
    }

    /// Returns the SF Symbol name describing the item's media format type.
    public static func pictogramName(for item: MediaSourceItem) -> String {
        formatInfo(for: item).pictogramName
    }

    /// Formats the item's type or file extension into an uppercase badge string.
    public static func label(for item: MediaSourceItem) -> String {
        formatInfo(for: item).label
    }

    /// Returns a distinctive format accent color matching the design system.
    public static func color(for item: MediaSourceItem) -> Color {
        formatInfo(for: item).color
    }

    /// Returns the accent color for a video extension.
    public static func videoColor(forExtension ext: String) -> Color {
        let normalized = ext.trimmingCharacters(in: .punctuationCharacters).lowercased()
        switch normalized {
        case "mp4":
            return Color.blue
        case "mov":
            return Color.cyan
        case "m4v":
            return Color.indigo
        case "mkv":
            return Color(red: 0.58, green: 0.28, blue: 0.88)
        case "avi":
            return Color.orange
        case "webm":
            return Color(red: 0.16, green: 0.68, blue: 0.38)
        case "flv", "f4v":
            return Color(red: 0.90, green: 0.25, blue: 0.25)
        case "wmv", "asf":
            return Color(red: 0.94, green: 0.62, blue: 0.12)
        case "ts", "m2ts", "mts":
            return Color.mint
        case "ogv":
            return Color(red: 0.20, green: 0.70, blue: 0.50)
        case "3gp":
            return Color.teal
        default:
            return Color(white: 0.30)
        }
    }

    /// Returns the accent color for a photo or document extension, factoring in `PhotoSubtype`.
    public static func photoColor(forExtension ext: String, subtype: PhotoSubtype = .standard) -> Color {
        switch subtype {
        case .livePhoto:
            return Color.yellow.opacity(0.9)
        case .hdr:
            return Color.purple
        case .panorama:
            return Color.indigo
        case .portrait:
            return Color.pink
        case .screenshot:
            return Color.mint
        case .raw:
            return Color(red: 0.58, green: 0.28, blue: 0.88)
        case .animated:
            return Color.orange
        case .standard:
            break
        }
        let normalized = ext.trimmingCharacters(in: .punctuationCharacters).lowercased()
        switch normalized {
        case "png":
            return Color.teal
        case "jpg", "jpeg", "jpe", "jfif":
            return Color.green
        case "heic", "heif":
            return Color.cyan
        case "webp", "avif":
            return Color.blue
        case "gif":
            return Color.orange
        case "pdf":
            return Color(red: 0.90, green: 0.25, blue: 0.25)
        case "dng", "cr2", "cr3", "nef", "arw", "raw", "orf", "rw2":
            return Color(red: 0.58, green: 0.28, blue: 0.88)
        case "tif", "tiff":
            return Color.indigo
        default:
            return Color(white: 0.30)
        }
    }
}
