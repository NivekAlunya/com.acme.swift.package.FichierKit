//
//  SMBVideoThumbnailTests.swift
//  FichierKitTests
//
//

import Foundation
import Testing
import FichierKit
#if canImport(UIKit)
import UIKit
#endif

@Suite("SMB & Local Video Thumbnail Tests")
struct SMBVideoThumbnailTests {
    #if canImport(UIKit) && canImport(AVFoundation) && canImport(CoreVideo)
    @Test("Generates non-nil thumbnail from local MP4 file")
    func testLocalVideoThumbnailGeneration() async throws {
        let tempVideoURL = try await VideoTestFixtureGenerator.createSampleMP4File()
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        let loader = SMBVideoThumbnailLoader()
        let image = await loader.loadThumbnail(
            from: tempVideoURL,
            fileName: "sample.mp4",
            targetSize: CGSize(width: 380, height: 260)
        )

        let unwrapped = try #require(image)
        #expect(unwrapped.size.width > 0)
        #expect(unwrapped.size.height > 0)

        // Second call serves from in-memory cache even if source file is removed
        try? FileManager.default.removeItem(at: tempVideoURL)
        let cachedImage = await loader.loadThumbnail(
            from: tempVideoURL,
            fileName: "sample.mp4",
            targetSize: CGSize(width: 120, height: 80)
        )
        #expect(cachedImage != nil)
    }

    @Test("Generates video thumbnail over SMBStreamingServer from SMB video file")
    func testSMBVideoThumbnailGenerationOverLoopback() async throws {
        let tempVideoURL = try await VideoTestFixtureGenerator.createSampleMP4File()
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        let mp4Data = try Data(contentsOf: tempVideoURL)
        let server = SavedSMBConnection(host: "192.168.1.50", username: "kevin", lastConnected: Date())
        let client = MockSMBClient(mockShares: ["Movies"], mockFileData: ["Movies/trailer.mp4": mp4Data])
        let sharesSource = SharesMediaSource(server: server, client: client)

        let resolver = DefaultMediaSourceResolver()
        await resolver.register(source: sharesSource)

        let loader = SMBVideoThumbnailLoader()
        let thumbnail = await loader.loadThumbnail(
            sourceID: server.id,
            share: "Movies",
            path: "trailer.mp4",
            fileName: "trailer.mp4",
            fileSize: Int64(mp4Data.count),
            targetSize: CGSize(width: 380, height: 260),
            resolver: resolver
        )

        let image = try #require(thumbnail)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)

        // Also verifies dynamic fileSize resolution when fileSize == 0 in directory listing
        let zeroSizeThumb = await loader.loadThumbnail(
            sourceID: server.id,
            share: "Movies",
            path: "trailer.mp4",
            fileName: "trailer_zero.mp4",
            fileSize: 0,
            targetSize: CGSize(width: 120, height: 80),
            resolver: resolver
        )
        let resolvedZeroImage = try #require(zeroSizeThumb)
        #expect(resolvedZeroImage.size.width > 0)
    }

    @Test("SMBStreamingServer serves HTTP 200 OK with full streamed payload for unranged GET exceeding chunk size")
    func testStreamingServerUnrangedGET() async throws {
        let payloadSize = (1200 * 1024) + 137 // > 2 x 512 KB chunks
        let expectedBytes = Data((0..<payloadSize).map { UInt8($0 & 0xFF) })
        let client = MockSMBClient(
            mockShares: ["Movies"],
            mockFileData: ["Movies/large.bin": expectedBytes]
        )

        let server = SMBStreamingServer(
            client: client,
            share: "Movies",
            path: "large.bin",
            fileName: "large.bin",
            totalSize: Int64(expectedBytes.count)
        )
        let streamURL = try await server.start()

        let (data, response) = try await URLSession.shared.data(from: streamURL)
        await server.stop()

        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(data == expectedBytes)
    }

    @Test("Concurrent mixed image and video thumbnail loads do not starve SMB video extraction")
    func testMixedMediaConcurrentThumbnailsDoNotStarveVideo() async throws {
        let tempVideoURL = try await VideoTestFixtureGenerator.createSampleMP4File()
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }
        let mp4Data = try Data(contentsOf: tempVideoURL)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let imgData = try #require(renderer.image { ctx in
            UIColor.systemGreen.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }.pngData())

        var files: [String: Data] = [
            "Movies/native.mp4": mp4Data,
            "Movies/extended.mkv": mp4Data
        ]
        for idx in 0..<4 {
            files["Movies/photo_\(idx).png"] = imgData
        }

        let server = SavedSMBConnection(host: "192.168.1.52", username: "kevin", lastConnected: Date())
        let client = MockSMBClient(mockShares: ["Movies"], mockFileData: files)
        let sharesSource = SharesMediaSource(server: server, client: client)
        let resolver = DefaultMediaSourceResolver()
        await resolver.register(source: sharesSource)

        let imageLoader = SMBImageLoader()
        let videoLoader = SMBVideoThumbnailLoader()

        async let p0 = imageLoader.loadThumbnail(sourceID: server.id, share: "Movies", path: "photo_0.png", targetSize: CGSize(width: 380, height: 260), resolver: resolver)
        async let p1 = imageLoader.loadThumbnail(sourceID: server.id, share: "Movies", path: "photo_1.png", targetSize: CGSize(width: 380, height: 260), resolver: resolver)
        async let p2 = imageLoader.loadThumbnail(sourceID: server.id, share: "Movies", path: "photo_2.png", targetSize: CGSize(width: 380, height: 260), resolver: resolver)
        async let p3 = imageLoader.loadThumbnail(sourceID: server.id, share: "Movies", path: "photo_3.png", targetSize: CGSize(width: 380, height: 260), resolver: resolver)
        async let nativeVid = videoLoader.loadThumbnail(sourceID: server.id, share: "Movies", path: "native.mp4", fileName: "native.mp4", fileSize: Int64(mp4Data.count), resolver: resolver)
        async let extVid = videoLoader.loadThumbnail(sourceID: server.id, share: "Movies", path: "extended.mkv", fileName: "extended.mkv", fileSize: Int64(mp4Data.count), resolver: resolver)

        let results = await (p0, p1, p2, p3, nativeVid, extVid)
        #expect(results.0 != nil)
        #expect(results.1 != nil)
        #expect(results.2 != nil)
        #expect(results.3 != nil)
        #expect(results.4 != nil)
        #expect(results.5 != nil)
    }

    @Test("VLCVideoThumbnailActor extracts frame from extended video streamed over SMBStreamingServer")
    func testVLCVideoThumbnailExtractionOverLoopback() async throws {
        let tempVideoURL = try await VideoTestFixtureGenerator.createSampleMP4File()
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        let mp4Data = try Data(contentsOf: tempVideoURL)
        let server = SavedSMBConnection(host: "192.168.1.51", username: "kevin", lastConnected: Date())
        let client = MockSMBClient(mockShares: ["Movies"], mockFileData: ["Movies/clip.mkv": mp4Data])
        let sharesSource = SharesMediaSource(server: server, client: client)

        let resolver = DefaultMediaSourceResolver()
        await resolver.register(source: sharesSource)

        let streamServer = SMBStreamingServer(
            client: client,
            share: "Movies",
            path: "clip.mkv",
            fileName: "clip.mkv",
            totalSize: Int64(mp4Data.count)
        )
        let streamURL = try await streamServer.start()
        let vlcThumb = await VLCVideoThumbnailActor.shared.generateThumbnail(
            from: streamURL,
            maxDimension: 560,
            snapshotPosition: 0.0,
            timeoutSeconds: 8.0
        )
        await streamServer.stop()

        let directImage = try #require(vlcThumb)
        #expect(directImage.size.width > 0)

        let loader = SMBVideoThumbnailLoader()
        let loaderThumb = await loader.loadThumbnail(
            sourceID: server.id,
            share: "Movies",
            path: "clip.mkv",
            fileName: "clip.mkv",
            fileSize: Int64(mp4Data.count),
            targetSize: CGSize(width: 380, height: 260),
            resolver: resolver
        )
        let resolvedImage = try #require(loaderThumb)
        #expect(resolvedImage.size.height > 0)
    }

    @Test("Loads downsampled local image thumbnail")
    func testLocalImageThumbnailGeneration() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let testImage = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let pngURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichierkit_img_\(UUID().uuidString).png")
        try testImage.pngData()?.write(to: pngURL)
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let loader = SMBImageLoader()
        let decoded = await loader.loadLocalThumbnail(url: pngURL, targetSize: CGSize(width: 120, height: 80))
        let unwrapped = try #require(decoded)
        #expect(unwrapped.size.width > 0)
    }
    #endif

    @Test("Returns nil safely for unsupported or missing video assets")
    func testUnsupportedAndMissingVideoSafelyReturnNil() async {
        let loader = SMBVideoThumbnailLoader()
        let missingURL = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID().uuidString).mkv")
        let missingThumb = await loader.loadThumbnail(from: missingURL, fileName: "missing.mkv")
        #expect(missingThumb == nil)

        let nonVideoURL = URL(fileURLWithPath: "/tmp/notes_\(UUID().uuidString).txt")
        let nonVideoThumb = await loader.loadThumbnail(from: nonVideoURL, fileName: "notes.txt")
        #expect(nonVideoThumb == nil)
    }

    @Test("VLCVideoThumbnailActor returns nil cleanly on missing URL and timeout")
    func testVLCVideoThumbnailActorMissingAndTimeout() async {
        let missingFile = URL(fileURLWithPath: "/tmp/missing_vlc_\(UUID().uuidString).mkv")
        let fileResult = await VLCVideoThumbnailActor.shared.generateThumbnail(
            from: missingFile,
            maxDimension: 260,
            snapshotPosition: 0.05,
            timeoutSeconds: 0.5
        )
        #expect(fileResult == nil)

        let unreachableHTTP = URL(string: "http://127.0.0.1:1/unreachable.webm") ?? URL(fileURLWithPath: "/")
        let timeoutResult = await VLCVideoThumbnailActor.shared.generateThumbnail(
            from: unreachableHTTP,
            maxDimension: 260,
            snapshotPosition: 0.0,
            timeoutSeconds: 0.3
        )
        #expect(timeoutResult == nil)
    }

    @Test("SMBVideoThumbnailLimiter handles concurrent permits and cancellation")
    func testLimiterCancellationAndConcurrency() async throws {
        let limiter = SMBVideoThumbnailLimiter(maxConcurrent: 1)

        let cancelledTask = Task<Bool, Never> {
            do {
                return try await limiter.withPermit {
                    try await Task.sleep(for: .milliseconds(500))
                    return true
                }
            } catch {
                return false
            }
        }
        cancelledTask.cancel()
        let cancelledResult = await cancelledTask.value
        #expect(!cancelledResult)

        let normalResult = try await limiter.withPermit {
            42
        }
        #expect(normalResult == 42)
    }
}
