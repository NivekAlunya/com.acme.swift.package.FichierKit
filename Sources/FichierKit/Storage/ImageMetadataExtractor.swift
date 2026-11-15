//
//  ImageMetadataExtractor.swift
//  FichierKit
//

import Foundation
import CoreGraphics
import ImageIO

/// High-performance metadata parser extracting EXIF, TIFF, and camera hardware tags from image sources.
///
/// ### Architecture & Concurrency
/// - **Zero-Decode Metadata Parsing**: Reads headers directly using `CGImageSourceCreateWithData` and `CGImageSourceCopyPropertiesAtIndex`
///   with `kCGImageSourceShouldCache: false`. This avoids allocating image bitmaps or decoding pixels into memory.
/// - **Thread Safety**: Marked `nonisolated public enum`, allowing execution from any concurrent background worker task.
nonisolated public enum ImageMetadataExtractor {
    
    /// Extracts EXIF and camera metadata directly from a local file URL.
    ///
    /// - Parameters:
    ///   - url: The file system URL of the image.
    ///   - fileName: The display file name.
    ///   - fileSize: Formatted human-readable file size string.
    /// - Returns: A populated `PictureEXIFData` structure.
    public static func extract(from url: URL, fileName: String, fileSize: String) -> PictureEXIFData {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return emptyData(fileName: fileName, fileSize: fileSize)
        }
        return extract(fromSource: source, fileName: fileName, fileSize: fileSize)
    }
    
    /// Extracts EXIF and camera metadata directly from in-memory byte data or partial header packets.
    ///
    /// - Parameters:
    ///   - data: Encoded image data (e.g. first 64 KB of a JPEG or HEIC file).
    ///   - fileName: The display file name.
    ///   - fileSize: Formatted human-readable file size string.
    /// - Returns: A populated `PictureEXIFData` structure.
    public static func extract(from data: Data, fileName: String, fileSize: String) -> PictureEXIFData {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return emptyData(fileName: fileName, fileSize: fileSize)
        }
        return extract(fromSource: source, fileName: fileName, fileSize: fileSize)
    }
    
    /// Fallback generator producing an empty EXIF record when image headers cannot be parsed.
    private static func emptyData(fileName: String, fileSize: String) -> PictureEXIFData {
        PictureEXIFData(
            fileName: fileName,
            fileSize: fileSize,
            dimensions: nil,
            megapixels: nil,
            cameraModel: nil,
            lensModel: nil,
            focalLength: nil,
            aperture: nil,
            shutterSpeed: nil,
            iso: nil,
            dateTaken: nil,
            fileFormat: (fileName as NSString).pathExtension.uppercased()
        )
    }
    
    /// Core extractor parsing dictionary trees returned by `CGImageSourceCopyPropertiesAtIndex`.
    ///
    /// ### Complex Code Breakdown:
    /// - **Dimension Resolution**: Checks root dictionary `kCGImagePropertyPixelWidth` first, falling back to EXIF tags.
    /// - **Megapixel Computation**: Computes `(width * height) / 1,000,000` to format standard photo MP strings.
    /// - **Camera Model Formatting**: Checks if `model` already contains `make` (e.g. "Canon Canon EOS R5") to avoid redundant prefixes.
    /// - **Exposure Conversion**: Converts decimal exposure seconds (e.g. 0.004s) into standard photographic fractions (`1/250s`).
    ///
    /// - Parameters:
    ///   - source: Initialized `CGImageSource`.
    ///   - fileName: Display name.
    ///   - fileSize: Formatted size string.
    /// - Returns: A fully configured `PictureEXIFData` model.
    private static func extract(fromSource source: CGImageSource, fileName: String, fileSize: String) -> PictureEXIFData {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return emptyData(fileName: fileName, fileSize: fileSize)
        }
        
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        
        // Dimensions & Megapixels
        var dimString: String?
        var megaPixelsString: String?
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? exif?[kCGImagePropertyExifPixelXDimension] as? Int
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? exif?[kCGImagePropertyExifPixelYDimension] as? Int
        
        if let w = width, let h = height {
            dimString = "\(w) × \(h)"
            let mp = Double(w * h) / 1_000_000.0
            megaPixelsString = String(format: "%.1f MP", mp)
        }
        
        // Camera & Lens
        let make = tiff?[kCGImagePropertyTIFFMake] as? String
        let model = tiff?[kCGImagePropertyTIFFModel] as? String
        var camera: String?
        if let model {
            if let make, !model.localizedCaseInsensitiveContains(make) {
                camera = "\(make) \(model)"
            } else {
                camera = model
            }
        }
        
        let lens = exif?[kCGImagePropertyExifLensModel] as? String
        
        // Exposure: Aperture, Shutter, ISO, Focal Length
        var apertureStr: String?
        if let fNumber = exif?[kCGImagePropertyExifFNumber] as? Double {
            apertureStr = String(format: "ƒ/%.1f", fNumber)
        }
        
        var shutterStr: String?
        if let expTime = exif?[kCGImagePropertyExifExposureTime] as? Double {
            if expTime >= 1.0 {
                shutterStr = String(format: "%.1fs", expTime)
            } else if expTime > 0 {
                let denom = Int(round(1.0 / expTime))
                shutterStr = "1/\(denom)s"
            }
        }
        
        var isoStr: String?
        if let isoArray = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int], let first = isoArray.first {
            isoStr = "ISO \(first)"
        }
        
        var focalStr: String?
        if let fl = exif?[kCGImagePropertyExifFocalLength] as? Double {
            focalStr = String(format: "%.0f mm", fl)
        }
        
        // Timestamp
        let dateTaken = exif?[kCGImagePropertyExifDateTimeOriginal] as? String ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        
        return PictureEXIFData(
            fileName: fileName,
            fileSize: fileSize,
            dimensions: dimString,
            megapixels: megaPixelsString,
            cameraModel: camera,
            lensModel: lens,
            focalLength: focalStr,
            aperture: apertureStr,
            shutterSpeed: shutterStr,
            iso: isoStr,
            dateTaken: dateTaken,
            fileFormat: (fileName as NSString).pathExtension.uppercased()
        )
    }
}
