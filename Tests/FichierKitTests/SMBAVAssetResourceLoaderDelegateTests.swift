//
//  SMBAVAssetResourceLoaderDelegateTests.swift
//  FichierKitTests
//

import AVFoundation
import Foundation
import Testing
@testable import FichierKit

@Suite("SMBAVAssetResourceLoaderDelegate Tests")
struct SMBAVAssetResourceLoaderDelegateTests {
    @Test("makeStreamURL uses smbstream scheme and preserves or defaults extension")
    func makeStreamURLFormatting() {
        let movURL = SMBAVAssetResourceLoaderDelegate.makeStreamURL(fileName: "clip.mov")
        #expect(movURL.scheme == SMBAVAssetResourceLoaderDelegate.scheme)
        #expect(movURL.pathExtension == "mov")

        let noExtURL = SMBAVAssetResourceLoaderDelegate.makeStreamURL(fileName: "video")
        #expect(noExtURL.scheme == SMBAVAssetResourceLoaderDelegate.scheme)
        #expect(noExtURL.pathExtension == "mp4")
    }

    @Test("AVURLAsset fails cleanly when fileSize is zero")
    func zeroFileSizeFailsCleanly() async {
        let client = RangeOnlyMockSMBClient()
        let delegate = SMBAVAssetResourceLoaderDelegate(
            client: client,
            share: "Media",
            path: "/empty.mp4",
            fileName: "empty.mp4",
            fileSize: 0
        )
        let url = SMBAVAssetResourceLoaderDelegate.makeStreamURL(fileName: "empty.mp4")
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(delegate, queue: FichierResourceLoaderQueue.shared)
        defer {
            delegate.cancelAll()
            asset.cancelLoading()
            asset.resourceLoader.setDelegate(nil, queue: nil)
        }

        await #expect(throws: (any Error).self) {
            _ = try await asset.load(.duration)
        }
    }

    @Test("AVURLAsset streams byte ranges from mock SMBClientProtocol")
    func streamsByteRangesFromMockClient() async throws {
        let videoURL = try await VideoTestFixtureGenerator.createMultiKeyframeMP4File(seconds: 2)
        defer { try? FileManager.default.removeItem(at: videoURL) }
        let mp4Data = try Data(contentsOf: videoURL)

        let client = RangeOnlyMockSMBClient(files: ["Media/sample.mp4": mp4Data])
        let delegate = SMBAVAssetResourceLoaderDelegate(
            client: client,
            share: "Media",
            path: "sample.mp4",
            fileName: "sample.mp4",
            fileSize: Int64(mp4Data.count),
            chunkSize: 64 * 1024
        )
        let streamURL = SMBAVAssetResourceLoaderDelegate.makeStreamURL(fileName: "sample.mp4")
        let asset = AVURLAsset(url: streamURL)
        asset.resourceLoader.setDelegate(delegate, queue: FichierResourceLoaderQueue.shared)
        defer {
            delegate.cancelAll()
            asset.cancelLoading()
            asset.resourceLoader.setDelegate(nil, queue: nil)
        }

        let duration = try await asset.load(.duration)
        #expect(duration.seconds > 1.0)

        let ranges = await client.recordedRanges
        #expect(!ranges.isEmpty)
    }
}
