//
//  SendableAVAssetImageGenerator.swift
//  FichierKit
//
//

import AVFoundation

#if canImport(UIKit)
/// Thread-safe `@unchecked Sendable` wrapper around `AVAssetImageGenerator` so
/// `cancelAllCGImageGeneration()` can be invoked from `withTaskCancellationHandler`'s `onCancel` closure.
final class SendableAVAssetImageGenerator: @unchecked Sendable {
    let generator: AVAssetImageGenerator

    init(asset: AVAsset) {
        self.generator = AVAssetImageGenerator(asset: asset)
    }

    func cancelAll() {
        generator.cancelAllCGImageGeneration()
    }
}
#endif
