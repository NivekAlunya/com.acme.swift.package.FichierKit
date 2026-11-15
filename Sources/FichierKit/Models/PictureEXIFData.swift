//
//  PictureEXIFData.swift
//  FichierKit
//

import Foundation

/// Parsed metadata container presenting EXIF, TIFF, and camera exposure information for a photo.
///
/// Constructed by `ImageMetadataExtractor` from image headers without decoding raw pixel buffers,
/// safely conforming to `Sendable` for transfer across actor isolation domains.
nonisolated public struct PictureEXIFData: Identifiable, Sendable {
    /// Identifiable conformance key mapped to the file name.
    public var id: String { fileName }
    
    /// File base name with extension (e.g. `DSC_4920.ARW`).
    public let fileName: String
    
    /// Human-readable file size string (e.g. `24.5 MB`).
    public let fileSize: String
    
    /// Image pixel dimensions formatted as `width × height`.
    public let dimensions: String?
    
    /// Sensor resolution formatted in megapixels (e.g. `24.2 MP`).
    public let megapixels: String?
    
    /// Camera body manufacturer and model (e.g. `Sony ILCE-7RM4`).
    public let cameraModel: String?
    
    /// Attached lens descriptor (e.g. `FE 24-70mm F2.8 GM`).
    public let lensModel: String?
    
    /// Optical focal length formatted in millimeters (e.g. `50 mm`).
    public let focalLength: String?
    
    /// Aperture f-stop number formatted as `f/2.8`.
    public let aperture: String?
    
    /// Exposure duration formatted in seconds or fractional notation (e.g. `1/250s`).
    public let shutterSpeed: String?
    
    /// Sensor sensitivity rating formatted as `ISO 400`.
    public let iso: String?
    
    /// Original capture date and time timestamp.
    public let dateTaken: String?
    
    /// Container or codec format identifier (e.g. `JPEG`, `HEIC`, `Sony RAW`).
    public let fileFormat: String?
    
    public init(
        fileName: String,
        fileSize: String,
        dimensions: String?,
        megapixels: String?,
        cameraModel: String?,
        lensModel: String?,
        focalLength: String?,
        aperture: String?,
        shutterSpeed: String?,
        iso: String?,
        dateTaken: String?,
        fileFormat: String?
    ) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.dimensions = dimensions
        self.megapixels = megapixels
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.focalLength = focalLength
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.iso = iso
        self.dateTaken = dateTaken
        self.fileFormat = fileFormat
    }
}
