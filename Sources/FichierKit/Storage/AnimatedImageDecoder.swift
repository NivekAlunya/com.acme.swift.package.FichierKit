//
//  AnimatedImageDecoder.swift
//  FichierKit
//

#if canImport(UIKit)
import UIKit
import ImageIO

/// High-performance decoder converting multi-frame animated image data (GIF, animated WebP, and APNG) into animated `UIImage` instances.
///
/// ### Architecture & ImageIO Deep-Dive
/// - Standard `UIImage(data:)` only renders the first frame of multi-frame animated image assets.
/// - This decoder iterates through `CGImageSourceGetCount`, extracts individual frame bitmaps, and reads
///   unclamped frame delays from the underlying ImageIO metadata dictionaries (`kCGImagePropertyGIFDictionary`
///   and `kCGImagePropertyWebPDictionary`).
/// - Marked `nonisolated public enum: Sendable` for concurrent execution across background decoding tasks.
nonisolated public enum AnimatedImageDecoder: Sendable {
    
    /// Decodes image data, returning an animated `UIImage` if multiple frames are present, or a standard static `UIImage`.
    ///
    /// ### Complex Code Breakdown:
    /// - **Single-Frame Short-Circuit**: Checks `CGImageSourceGetCount(source) > 1`. If single-frame, defaults to standard decode.
    /// - **Frame Accumulation**: Extracts each frame with `CGImageSourceCreateImageAtIndex` and aggregates frame duration.
    /// - **Duration Clamping**: If metadata reports zero or negative total duration, enforces a standard 10 FPS fallback (`0.1s` per frame).
    ///
    /// - Parameter data: Raw encoded image bytes.
    /// - Returns: A composite animated `UIImage`, a static `UIImage`, or `nil` on corrupt data.
    nonisolated public static func decode(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            return UIImage(data: data)
        }
        
        let frames: [(image: UIImage, duration: Double)] = (0..<count).compactMap { i in
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { return nil }
            return (UIImage(cgImage: cgImage), getFrameDuration(from: source, at: i))
        }

        guard !frames.isEmpty else {
            return UIImage(data: data)
        }

        let images = frames.map(\.image)
        let totalDuration = frames.reduce(0.0) { $0 + $1.duration }
        let duration = totalDuration <= 0 ? Double(count) * 0.1 : totalDuration

        return UIImage.animatedImage(with: images, duration: duration) ?? UIImage(data: data)
    }
    
    /// Extracts the display delay duration (in seconds) for a specific frame index from GIF or WebP property dictionaries.
    ///
    /// Prefers `kCGImagePropertyGIFUnclampedDelayTime` over `kCGImagePropertyGIFDelayTime` to avoid legacy 100ms browser clamp limits.
    ///
    /// - Parameters:
    ///   - source: The initialized `CGImageSource` reference.
    ///   - index: The zero-based frame index.
    /// - Returns: The frame duration in seconds (defaults to `0.1s`).
    nonisolated private static func getFrameDuration(from source: CGImageSource, at index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }
        
        // GIF Frame Delay (prefer unclamped time to preserve high-framerate animations)
        if let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
                return unclamped
            }
            if let delay = gifDict[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
                return delay
            }
        }
        
        // WebP Frame Delay
        if let webpDict = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            if let unclamped = webpDict[kCGImagePropertyWebPUnclampedDelayTime] as? Double, unclamped > 0 {
                return unclamped
            }
            if let delay = webpDict[kCGImagePropertyWebPDelayTime] as? Double, delay > 0 {
                return delay
            }
        }
        
        return 0.1
    }
}
#endif
