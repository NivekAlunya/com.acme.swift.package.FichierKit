//
//  PhotoExportSessionBox.swift
//  FichierKit
//

#if canImport(AVFoundation)
import AVFoundation

/// Transfers a freshly created `AVAssetExportSession` from the PhotoKit callback to the awaiting task.
///
/// Marked `@unchecked Sendable` because `AVAssetExportSession` is not annotated `Sendable` by AVFoundation.
/// Safe because the session is created in the callback, never touched afterwards by the creator,
/// and consumed exactly once by `PhotoVideoLoader`.
struct PhotoExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
}
#endif
