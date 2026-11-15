//
//  PhotoLibrarySaver.swift
//  FichierKit
//

#if canImport(Photos) && canImport(UIKit) && !os(tvOS)
import UIKit
import Photos

/// Utility service responsible for safely exporting images and video files into the user's system Photos library.
///
/// ### Permissions & Concurrency
/// - **Actor Isolation**: Explicitly bound to `@MainActor`, synchronizing authorization dialog presentation with the UI.
/// - **Least-Privilege Authorization**: Requests `PHAccessLevel.addOnly` permission rather than read/write access,
///   respecting modern iOS user privacy guidelines without requiring access to the user's existing photos.
@MainActor
public enum PhotoLibrarySaver {
    
    /// Verifies or prompts for write-only PhotoKit authorization.
    ///
    /// - Throws: `CocoaError(.fileWriteNoPermission)` if authorization was denied or restricted.
    private static func ensureAuthorization() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }
    
    /// Exports an in-memory image into the user's Camera Roll / Photos library.
    ///
    /// - Parameter image: The `UIImage` instance to save.
    /// - Throws: `CocoaError` or `PHPhotosError` if authorization fails or asset creation is rejected.
    public static func saveImageToPhotos(_ image: UIImage) async throws {
        try await ensureAuthorization()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
    
    /// Exports a local on-disk video file into the user's Camera Roll / Photos library.
    ///
    /// - Parameter fileURL: The file system `URL` referencing the video file.
    /// - Throws: `CocoaError` or `PHPhotosError` if authorization fails or asset creation is rejected.
    public static func saveVideoToPhotos(at fileURL: URL) async throws {
        try await ensureAuthorization()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }
    }
}
#endif
