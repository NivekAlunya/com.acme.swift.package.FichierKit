//
//  PictureEXIFBox.swift
//  FichierKit
//

import Foundation

/// Reference-type wrapper enclosing value-type `PictureEXIFData` to enable storage inside Objective-C-derived `NSCache` collections.
///
/// ### Architecture & Concurrency
/// - **NSCache Compatibility**: `NSCache` requires both `Key` and `Value` to conform to `AnyObject` (`NSObject`).
/// - **Swift 6 Concurrency**: Marked `nonisolated public final class` conforming to `Sendable` because its wrapped `value` property is immutable.
nonisolated public final class PictureEXIFBox: NSObject, Sendable {
    
    /// The immutable EXIF metadata payload.
    public let value: PictureEXIFData
    
    /// Wraps a value-type `PictureEXIFData` instance into an object reference.
    ///
    /// - Parameter value: The metadata model to box.
    public init(_ value: PictureEXIFData) {
        self.value = value
        super.init()
    }
}
