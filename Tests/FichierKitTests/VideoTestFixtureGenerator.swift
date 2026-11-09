//
//  VideoTestFixtureGenerator.swift
//  FichierKitTests
//
//

import Foundation
#if canImport(AVFoundation) && canImport(CoreVideo)
import AVFoundation
import CoreVideo
#endif

/// Synthesizes minimal valid `.mp4` test fixtures in temporary storage for thumbnailer verification.
enum VideoTestFixtureGenerator {
    #if canImport(AVFoundation) && canImport(CoreVideo)
    static func createSampleMP4File(width: Int = 160, height: Int = 120) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichierkit_test_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let (input, adaptor) = try configureVideoWriter(writer, width: width, height: height)

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "VideoTestFixtureGenerator", code: 2)
        }
        writer.startSession(atSourceTime: .zero)

        let timestamps = [
            CMTime(value: 0, timescale: 30),
            CMTime(value: 15, timescale: 30),
            CMTime(value: 30, timescale: 30)
        ]

        try await appendGrayFrames(timestamps: timestamps, width: width, height: height, input: input, adaptor: adaptor)

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "VideoTestFixtureGenerator", code: 5)
        }

        return outputURL
    }

    private static func configureVideoWriter(
        _ writer: AVAssetWriter,
        width: Int,
        height: Int
    ) throws -> (AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor) {
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let pixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelAttributes
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "VideoTestFixtureGenerator", code: 1)
        }
        writer.add(input)
        return (input, adaptor)
    }

    private static func appendGrayFrames(
        timestamps: [CMTime],
        width: Int,
        height: Int,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) async throws {
        for presentationTime in timestamps {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw NSError(domain: "VideoTestFixtureGenerator", code: 3)
            }
            var bufferOut: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &bufferOut)
            guard status == kCVReturnSuccess, let buffer = bufferOut else {
                throw NSError(domain: "VideoTestFixtureGenerator", code: 4)
            }

            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                memset(base, 0x7F, bytesPerRow * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: presentationTime)
        }
    }
    #endif
}
