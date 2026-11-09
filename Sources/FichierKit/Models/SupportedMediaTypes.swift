//
//  SupportedMediaTypes.swift
//  FichierKit
//
//

import Foundation
import UniformTypeIdentifiers

/// Centralized file extension registry and MIME type classification utility.
public enum SupportedMediaTypes: Sendable {
    /// Recognized raster, vector, animated, and camera RAW image file extensions (lowercase).
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "jif", "jfif",
        "png", "heic", "heif", "webp", "avif",
        "gif", "tiff", "tif", "bmp", "ico",
        "jp2", "j2k", "jpf", "jpx",
        "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "pef", "raf"
    ]

    /// Native video file extensions supported by AVFoundation hardware acceleration.
    public static let nativeVideoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "3gp"
    ]

    /// Extended video container and codec extensions decoded via VLCKit / LibVLC.
    public static let extendedVideoExtensions: Set<String> = [
        "mkv", "avi", "webm", "flv", "f4v", "wmv", "asf",
        "ts", "m2ts", "mts", "m2v", "mpg", "mpeg", "vob",
        "ogv", "rm", "mxf", "wtv", "hevc", "mjpeg"
    ]

    /// Unified union set of all recognized video file extensions.
    public static let videoExtensions: Set<String> = nativeVideoExtensions.union(extendedVideoExtensions)

    /// Unified union set of all supported media file extensions in tvOS media browsing.
    public static let allExtensions: Set<String> = imageExtensions.union(videoExtensions)

    /// Returns `true` if the extension represents a supported image or video file.
    public static func isSupported(extension ext: String) -> Bool {
        allExtensions.contains(ext.lowercased())
    }

    /// Returns `true` if the extension represents any video format.
    public static func isVideo(extension ext: String) -> Bool {
        videoExtensions.contains(ext.lowercased())
    }

    /// Returns `true` if the extension is natively decoded by AVFoundation.
    public static func isNativeVideo(extension ext: String) -> Bool {
        nativeVideoExtensions.contains(ext.lowercased())
    }

    /// Returns `true` if the extension requires VLCKit / extended demuxing.
    public static func isExtendedVideo(extension ext: String) -> Bool {
        extendedVideoExtensions.contains(ext.lowercased())
    }

    /// Returns `true` if the extension represents an image format.
    public static func isImage(extension ext: String) -> Bool {
        imageExtensions.contains(ext.lowercased())
    }

    /// Resolves the MIME content-type string for a given file extension.
    public static func mimeType(for ext: String) -> String {
        let normalized = ext.trimmingCharacters(in: .punctuationCharacters).lowercased()
        switch normalized {
        case "mkv":
            return "video/x-matroska"
        case "webm":
            return "video/webm"
        case "avi":
            return "video/x-msvideo"
        case "mp4":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "m4v":
            return "video/x-m4v"
        case "3gp":
            return "video/3gpp"
        case "flv", "f4v":
            return "video/x-flv"
        case "wmv", "asf":
            return "video/x-ms-wmv"
        case "ts", "m2ts", "mts":
            return "video/mp2t"
        case "mpg", "mpeg", "m2v", "vob":
            return "video/mpeg"
        case "ogv":
            return "video/ogg"
        case "rm":
            return "application/vnd.rn-realmedia"
        case "mxf":
            return "application/mxf"
        default:
            if let utType = UTType(filenameExtension: normalized), let mime = utType.preferredMIMEType {
                return mime
            }
            return "video/x-matroska"
        }
    }
}
