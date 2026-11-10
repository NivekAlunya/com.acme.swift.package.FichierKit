//
//  FichierKitTests.swift
//  FichierKitTests
//

import Foundation
import Testing
import FichierKit

@Suite("FichierKit Sources & Models Tests")
struct FichierKitTests {
    @Test("Verify MediaItemType Equatable")
    func testMediaItemType() {
        #expect(MediaItemType.folder == MediaItemType.folder)
        #expect(MediaItemType.image != MediaItemType.video)
    }

    @Test("Verify PhotosMediaSource Layout and Sort Keys")
    func testPhotosMediaSourceMetadata() {
        let photosSource = PhotosMediaSource()
        #expect(photosSource.id == "photos")
        #expect(photosSource.preferredLayout == .grid)
        #expect(photosSource.supportedSortKeys.contains(.date))
        #expect(photosSource.supportedSortKeys.contains(.name))
    }

    @Test("Verify SharesMediaSource Layout and Root Shares Fetching")
    func testSharesMediaSource() async throws {
        let server = SavedSMBConnection(
            host: "192.168.1.50",
            username: "kevin",
            lastConnected: Date(),
            hostname: "Mac mini"
        )
        let mockClient = MockSMBClient(mockShares: ["Movies", "Photos"])
        let sharesSource = SharesMediaSource(server: server, client: mockClient)

        #expect(sharesSource.preferredLayout == .list)
        #expect(sharesSource.supportedSortKeys.contains(.size))

        let rootItems = try await sharesSource.fetchItems(
            in: nil,
            sortBy: .name,
            order: .ascending,
            page: 0,
            pageSize: 10
        )

        #expect(rootItems.count == 2)
        #expect(rootItems[0].name == "Movies")
        #expect(rootItems[0].type == .folder)
        #expect(rootItems[1].name == "Photos")
        #expect(rootItems[1].type == .folder)
    }

    @Test("Verify SMBServerFormModel Validation and Serialization")
    func testSMBServerFormModel() {
        var form = SMBServerFormModel()
        #expect(!form.isValid)

        form.host = "192.168.1.100"
        #expect(!form.isValid)

        form.username = "admin"
        #expect(form.isValid)

        form.hostname = "Storage Server"
        let connection = form.makeConnection()
        #expect(connection.host == "192.168.1.100")
        #expect(connection.username == "admin")
        #expect(connection.displayName == "Storage Server [192.168.1.100]")

        form.hostname = ""
        #expect(form.makeConnection().displayName == "192.168.1.100")
    }

    @Test("Verify SMBError Descriptions")
    func testSMBErrorDescriptions() {
        let unreachable = SMBError.unreachable("192.168.1.50")
        #expect(unreachable.errorDescription?.contains("unreachable") == true)

        let badCreds = SMBError.badCredentials
        #expect(badCreds.errorDescription?.contains("Authentication failed") == true)

        let timeout = SMBError.timeout
        #expect(timeout.errorDescription?.contains("timed out") == true)
    }

    @Test("Verify DefaultSlideshowSettingsStore Persistence")
    func testSlideshowSettingsStore() async {
        let suiteName = "FichierKitTests_Slideshow_\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let store = DefaultSlideshowSettingsStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        let initialInterval = await store.loadInterval()
        let initialStyle = await store.loadTransitionStyle()
        #expect(initialInterval == 4.0)
        #expect(initialStyle == .slide)

        await store.saveInterval(10.0)
        await store.saveTransitionStyle(.fade)

        let updatedInterval = await store.loadInterval()
        let updatedStyle = await store.loadTransitionStyle()
        #expect(updatedInterval == 10.0)
        #expect(updatedStyle == .fade)
    }

    @Test("Verify DefaultVideoPlaybackStore Resume Thresholds")
    func testVideoPlaybackStore() async {
        let suiteName = "FichierKitTests_Playback_\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let store = DefaultVideoPlaybackStore(userDefaults: UserDefaults(suiteName: suiteName)!)

        // Too short (< 10s) -> ignored
        await store.savePlaybackPosition(itemID: "vid1", time: 5.0, duration: 120.0)
        #expect(await store.playbackPosition(for: "vid1") == nil)

        // Valid resume position -> persisted
        await store.savePlaybackPosition(itemID: "vid1", time: 45.0, duration: 120.0)
        #expect(await store.playbackPosition(for: "vid1") == 45.0)

        // Near end (within 15s of completion) -> cleared
        await store.savePlaybackPosition(itemID: "vid1", time: 110.0, duration: 120.0)
        #expect(await store.playbackPosition(for: "vid1") == nil)
    }

    @Test("Verify DefaultMediaSortPreferenceStore Per-Source Persistence")
    func testMediaSortPreferenceStore() async {
        let suiteName = "FichierKitTests_Sort_\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let store = DefaultMediaSortPreferenceStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        #expect(await store.preference(for: "photos") == nil)

        let pref = MediaSortPreference(key: .size, order: .descending)
        await store.savePreference(pref, for: "smb://server1")
        #expect(await store.preference(for: "smb://server1") == pref)
        #expect(await store.preference(for: "photos") == nil)
    }

    @Test("Verify DefaultMediaLayoutPreferenceStore Per-Source Persistence")
    func testMediaLayoutPreferenceStore() async {
        let suiteName = "FichierKitTests_Layout_\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let store = DefaultMediaLayoutPreferenceStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        #expect(await store.layout(for: "smb://server1") == nil)

        await store.saveLayout(.grid, for: "smb://server1")
        #expect(await store.layout(for: "smb://server1") == .grid)
        #expect(await store.layout(for: "photos") == nil)

        await store.saveLayout(.list, for: "photos")
        #expect(await store.layout(for: "photos") == .list)
        #expect(MediaSourceLayout.grid.toggled == .list)
        #expect(MediaSourceLayout.list.toggled == .grid)
    }

    @Test("Verify SupportedMediaTypes Classification and MIME Types")
    func testSupportedMediaTypes() {
        #expect(SupportedMediaTypes.isNativeVideo(extension: "mp4"))
        #expect(SupportedMediaTypes.isNativeVideo(extension: "MOV"))
        #expect(!SupportedMediaTypes.isExtendedVideo(extension: "mp4"))

        #expect(SupportedMediaTypes.isExtendedVideo(extension: "mkv"))
        #expect(SupportedMediaTypes.isExtendedVideo(extension: "AVI"))
        #expect(SupportedMediaTypes.isVideo(extension: "mkv"))
        #expect(SupportedMediaTypes.isImage(extension: "heic"))
        #expect(!SupportedMediaTypes.isSupported(extension: "txt"))

        #expect(SupportedMediaTypes.mimeType(for: "mkv") == "video/x-matroska")
        #expect(SupportedMediaTypes.mimeType(for: "mp4") == "video/mp4")
    }

    @Test("Verify HTTPRangeParser Byte Ranges")
    func testHTTPRangeParser() {
        let bounded = HTTPRangeParser.parse("Range: bytes=0-1023", totalSize: 4096)
        #expect(bounded?.start == 0)
        #expect(bounded?.end == 1023)

        let openEnded = HTTPRangeParser.parse("Range: bytes=512-", totalSize: 1000)
        #expect(openEnded?.start == 512)
        #expect(openEnded?.end == 999)

        let suffix = HTTPRangeParser.parse("Range: bytes=-200", totalSize: 1000)
        #expect(suffix?.start == 800)
        #expect(suffix?.end == 999)

        let overflow = HTTPRangeParser.parse("Range: bytes=2000-3000", totalSize: 1000)
        #expect(overflow == nil)

        let clamped = HTTPRangeParser.parse("Range: bytes=900-9999", totalSize: 1000)
        #expect(clamped?.start == 900)
        #expect(clamped?.end == 999)
    }

    @Test("Verify SharesMediaSource Populates SMB Context Metadata")
    func testSharesMediaSourceMetadataAndFolderDrilling() async throws {
        let server = SavedSMBConnection(host: "192.168.1.50", username: "kevin", lastConnected: Date())
        let mockMovie = MediaSourceItem(
            id: "movie1",
            name: "film.mkv",
            path: "Media/Movies/film.mkv",
            type: .video,
            size: 1234
        )
        let mockClient = MockSMBClient(mockShares: ["Media"], mockItems: [mockMovie])
        let source = SharesMediaSource(server: server, client: mockClient)

        let roots = try await source.fetchItems(in: nil, sortBy: .name, order: .ascending, page: 0, pageSize: 10)
        #expect(roots.count == 1)
        #expect(roots[0].sourceID == server.id)
        #expect(roots[0].smbShare == "Media")
        #expect(roots[0].smbPath == "")

        let children = try await source.fetchItems(in: roots[0], sortBy: .name, order: .ascending, page: 0, pageSize: 10)
        #expect(children.count == 1)
        #expect(children[0].sourceID == server.id)
        #expect(children[0].smbShare == "Media")
    }

    @Test("Verify MediaSortKey displayTitle and SharesMediaSource filename sorting keep folders first")
    func testSharesMediaSourceFilenameAndTypeSorting() async throws {
        #expect(MediaSortKey.name.displayTitle == "Filename")
        #expect(MediaSortKey.date.displayTitle == "Date")
        #expect(MediaSortKey.size.displayTitle == "Size")
        #expect(MediaSortKey.type.displayTitle == "Type")

        let server = SavedSMBConnection(host: "192.168.1.50", username: "kevin", lastConnected: Date())
        let mockItems = [
            MediaSourceItem(id: "f10", name: "File 10.mp4", path: "Media/File 10.mp4", type: .video, size: 100),
            MediaSourceItem(id: "f2", name: "File 2.jpg", path: "Media/File 2.jpg", type: .image, size: 200),
            MediaSourceItem(id: "d2", name: "Folder B", path: "Media/Folder B", type: .folder),
            MediaSourceItem(id: "d1", name: "Folder A", path: "Media/Folder A", type: .folder)
        ]
        let mockClient = MockSMBClient(mockShares: ["Media"], mockItems: mockItems)
        let source = SharesMediaSource(server: server, client: mockClient)
        let rootFolder = MediaSourceItem(
            id: "root",
            name: "Media",
            path: "Media",
            type: .folder,
            sourceID: server.id,
            smbShare: "Media",
            smbPath: ""
        )

        let asc = try await source.fetchItems(in: rootFolder, sortBy: .name, order: .ascending, page: 0, pageSize: 10)
        #expect(asc.map(\.name) == ["Folder A", "Folder B", "File 2.jpg", "File 10.mp4"])

        let desc = try await source.fetchItems(in: rootFolder, sortBy: .name, order: .descending, page: 0, pageSize: 10)
        #expect(desc.map(\.name) == ["Folder B", "Folder A", "File 10.mp4", "File 2.jpg"])

        let byTypeAsc = try await source.fetchItems(in: rootFolder, sortBy: .type, order: .ascending, page: 0, pageSize: 10)
        #expect(byTypeAsc.map(\.name) == ["Folder A", "Folder B", "File 2.jpg", "File 10.mp4"])
    }

    @Test("Verify DefaultMediaSourceResolver Resolves Saved SMB Servers")
    func testDefaultMediaSourceResolverSMB() async throws {
        let suiteName = "FichierKitTests_Resolver_\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let passwordStore = SMBPasswordStore(service: "test.resolver.\(UUID().uuidString)")
        let serverStore = DefaultSMBServerStore(
            userDefaults: UserDefaults(suiteName: suiteName)!,
            passwordStore: passwordStore
        )
        let resolver = DefaultMediaSourceResolver(serverStore: serverStore)

        let connection = SavedSMBConnection(host: "nas.local", username: "guest", lastConnected: Date(), hostname: "NAS")
        try await serverStore.saveServer(connection, password: "secret")

        let resolved = await resolver.resolve(sourceID: connection.id)
        #expect(resolved != nil)
        #expect(resolved?.id == connection.id)
        #expect(await resolver.smbClient(for: connection.id) != nil)

        await resolver.invalidateSource(id: connection.id)
        let unknown = await resolver.resolve(sourceID: "nonexistent@host")
        #expect(unknown == nil)
    }

    @Test("Verify DiscoveredHost Identity, SMBError.noShares, and Host Normalization")
    func testBonjourModelsAndHostNormalization() {
        var host = DiscoveredHost(name: "Mac mini", resolvedHost: nil)
        let initialID = host.id
        host.resolvedHost = "192.168.1.42"
        #expect(host.id == initialID)
        #expect(host.resolvedHost == "192.168.1.42")

        let noSharesError = SMBError.noShares
        #expect(noSharesError.errorDescription?.contains("No shared folders") == true)

        var form = SMBServerFormModel()
        form.host = "  smb://192.168.1.50%en0/Media  "
        form.username = "kevin"
        let normalized = form.makeConnection()
        #expect(normalized.host == "192.168.1.50")
    }

    @Test("Verify DefaultSMBConnectionValidator Rejects Invalid Host Format")
    func testConnectionValidatorHostValidation() async {
        let serverWithPort = SavedSMBConnection(
            host: "192.168.1.50:445",
            username: "kevin",
            lastConnected: Date()
        )
        let validator = DefaultSMBConnectionValidator()

        await #expect(throws: SMBError.self) {
            try await validator.validateAndListShares(for: serverWithPort, password: "pass")
        }
    }

    @Test("Verify SMBHostDiscovery Lifecycle State")
    @MainActor
    func testSMBHostDiscoveryLifecycle() {
        let discovery = SMBHostDiscovery()
        #expect(discovery.discoveredHosts.isEmpty)
        #expect(!discovery.isScanning)
        #expect(discovery.errorMessage == nil)

        discovery.stopDiscovery()
        #expect(!discovery.isScanning)
    }

    @Test("Verify SMBStreamingServer Serves Loopback Byte Ranges")
    func testSMBStreamingServerLoopbackRange() async throws {
        let payload = Data("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
        let client = MockSMBClient(mockFileData: ["Media/sample.mkv": payload])
        let server = SMBStreamingServer(
            client: client,
            share: "Media",
            path: "sample.mkv",
            fileName: "sample.mkv",
            totalSize: Int64(payload.count)
        )

        let streamURL = try await server.start()

        var request = URLRequest(url: streamURL)
        request.setValue("bytes=10-15", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        await server.stop()

        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(String(decoding: data, as: UTF8.self) == "ABCDEF")
    }

    @Test("Verify TVVLCPlayerEngine Initial and Seek State")
    @MainActor
    func testTVVLCPlayerEngineInitialAndSeekState() {
        let engine = TVVLCPlayerEngine()
        #expect(engine.playbackState == .idle)
        #expect(engine.currentTime == 0)
        #expect(engine.duration == 0)
        #expect(!engine.isPlaying)

        engine.seek(to: 42.0)
        #expect(engine.currentTime == 42.0)
        engine.seek(to: 84.0, precision: .fast)
        #expect(engine.currentTime == 84.0)
        #expect(engine.availableChapters.isEmpty)

        let avEngine = AVPlayerEngine()
        avEngine.onDurationUpdate?(300.0)
        avEngine.seek(to: 120.0, precision: .fast)
        #expect(avEngine.currentTime == 120.0)
        #expect(avEngine.availableChapters.isEmpty)
        avEngine.tearDown()

        engine.tearDown()
        #expect(engine.playbackState == .idle)
        #expect(engine.currentTime == 0)
    }

    @Test("Verify Platform Document Support and GIF/PDF Helpers")
    func testDocumentAndGifHelpers() {
        #expect(SupportedMediaTypes.isGIF(extension: "gif"))
        #expect(SupportedMediaTypes.isGIF(extension: "GIF"))
        #expect(!SupportedMediaTypes.isGIF(extension: "png"))
        #expect(SupportedMediaTypes.mimeType(for: "pdf") == "application/pdf")
        #expect(SupportedMediaTypes.mimeType(for: ".pdf") == "application/pdf")

        #if !os(tvOS)
        #expect(SupportedMediaTypes.isDocument(extension: "pdf"))
        #expect(SupportedMediaTypes.isPDF(extension: "PDF"))
        #expect(SupportedMediaTypes.isSupported(extension: "pdf"))
        #expect(MediaItemType.document != MediaItemType.image)
        #else
        #expect(!SupportedMediaTypes.isDocument(extension: "pdf"))
        #expect(!SupportedMediaTypes.isPDF(extension: "pdf"))
        #expect(!SupportedMediaTypes.isSupported(extension: "pdf"))
        #endif
    }

    @Test("Verify PlayerPlaybackState Convenience Properties")
    func testPlayerPlaybackStateConvenience() {
        #expect(PlayerPlaybackState.playing.isPlaying)
        #expect(!PlayerPlaybackState.paused.isPlaying)
        #expect(!PlayerPlaybackState.idle.isPlaying)

        #expect(PlayerPlaybackState.loading.isBuffering)
        #expect(PlayerPlaybackState.buffering.isBuffering)
        #expect(!PlayerPlaybackState.playing.isBuffering)
        #expect(!PlayerPlaybackState.failed("err").isBuffering)
    }

    @Test("Verify SMBClientProtocol downloadFile and Cancellation")
    func testSMBDownloadFile() async throws {
        let payload = Data("Hello PDF Document Payload".utf8)
        let client = MockSMBClient(mockFileData: ["Docs/manual.pdf": payload])
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichierkit_dl_\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await client.downloadFile(share: "Docs", path: "manual.pdf", to: tempURL)
        let downloaded = try Data(contentsOf: tempURL)
        #expect(downloaded == payload)

        await #expect(throws: CancellationError.self) {
            try await client.downloadFile(share: "Docs", path: "manual.pdf", to: tempURL) { _, _ in
                false
            }
        }
    }

    @Test("Verify PlayerEngine Volume Mute Rate and Tolerance Seek Controls")
    @MainActor
    func testPlayerEngineExtendedControls() async {
        let avEngine = AVPlayerEngine()
        avEngine.volume = 0.45
        #expect(abs(avEngine.volume - 0.45) < 0.02)
        avEngine.isMuted = true
        #expect(avEngine.isMuted)
        avEngine.playbackRate = 1.5
        #expect(avEngine.playbackRate == 1.5)
        avEngine.seek(to: 12.0, toleranceBefore: 0, toleranceAfter: 0, completion: nil)
        #expect(avEngine.currentTime == 12.0)
        avEngine.seek(to: 13.0, toleranceBefore: .nan, toleranceAfter: -.infinity, completion: nil)
        #expect(avEngine.currentTime == 13.0)
        avEngine.seek(to: 14.0, toleranceBefore: .infinity, toleranceAfter: .nan, completion: nil)
        #expect(avEngine.currentTime == 14.0)
        avEngine.tearDown()

        let vlcEngine = TVVLCPlayerEngine()
        vlcEngine.volume = 0.75
        #expect(abs(vlcEngine.volume - 0.75) < 0.02)
        vlcEngine.isMuted = true
        #expect(vlcEngine.isMuted)
        vlcEngine.playbackRate = 2.0
        #expect(vlcEngine.playbackRate == 2.0)
        vlcEngine.seek(to: 25.0, toleranceBefore: .infinity, toleranceAfter: .infinity, completion: nil)
        #expect(vlcEngine.currentTime == 25.0)
        vlcEngine.tearDown()

        let delegate = SMBAVAssetResourceLoaderDelegate(
            client: MockSMBClient(),
            share: "Media",
            path: "clip.mp4",
            fileName: "clip.mp4",
            fileSize: 1024
        )
        let streamURL = SMBAVAssetResourceLoaderDelegate.makeStreamURL(fileName: "clip.mp4")
        #expect(streamURL.scheme == SMBAVAssetResourceLoaderDelegate.scheme)
        delegate.cancelAll()
    }

    @Test("Default SMB download streams multi-chunk files via bounded monotonic ranges without readFileData")
    func testDefaultSMBDownloadStreamsBoundedChunksWithProgress() async throws {
        let chunkSize = 1_048_576
        let payloadCount = (chunkSize * 2) + 302_848
        let payload = Data((0..<payloadCount).map { UInt8(($0 * 31 + 7) & 0xFF) })
        let client = RangeOnlyMockSMBClient(files: ["Media/large.bin": payload])

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichierkit_dl_multi_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let destURL = tempDir.appendingPathComponent("large.bin")
        let (progressStream, progressContinuation) = AsyncStream.makeStream(of: (Int64, Int64).self)

        try await client.downloadFile(share: "Media", path: "large.bin", to: destURL) { bytes, total in
            progressContinuation.yield((bytes, total))
            return true
        }
        progressContinuation.finish()

        var progressEvents: [(Int64, Int64)] = []
        for await event in progressStream {
            progressEvents.append(event)
        }

        let downloaded = try Data(contentsOf: destURL)
        #expect(downloaded == payload)
        #expect(await client.readFileDataCallCount == 0)

        let ranges = await client.recordedRanges
        #expect(ranges.count == 3)
        #expect(ranges.map(\.offset) == [0, Int64(chunkSize), Int64(chunkSize * 2)])
        #expect(ranges.map(\.length) == [chunkSize, chunkSize, 302_848])
        #expect(ranges.allSatisfy { $0.length > 0 && $0.length <= chunkSize })

        #expect(progressEvents.count == 3)
        #expect(progressEvents.map(\.0) == [Int64(chunkSize), Int64(chunkSize * 2), Int64(payloadCount)])
        #expect(progressEvents.allSatisfy { $0.1 == Int64(payloadCount) })

        let directoryEntries = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        #expect(directoryEntries == ["large.bin"])
    }

    @Test("Default SMB download handles zero-byte and unknown-size files without looping")
    func testDefaultSMBDownloadZeroByteAndUnknownSizeFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichierkit_dl_zero_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let zeroClient = RangeOnlyMockSMBClient(files: ["Docs/empty.bin": Data()])
        let emptyURL = tempDir.appendingPathComponent("empty.bin")
        try await zeroClient.downloadFile(share: "Docs", path: "empty.bin", to: emptyURL)

        let emptyData = try Data(contentsOf: emptyURL)
        #expect(emptyData.isEmpty)
        let zeroRanges = await zeroClient.recordedRanges
        #expect(zeroRanges.count == 1)
        #expect(zeroRanges.first?.offset == 0)
        #expect(zeroRanges.first?.length == 1_048_576)
        #expect(await zeroClient.readFileDataCallCount == 0)

        let unknownPayload = Data((0..<1_300_000).map { UInt8($0 & 0xFF) })
        let unknownClient = RangeOnlyMockSMBClient(
            files: ["Media/unknown.bin": unknownPayload],
            reportedSizes: ["Media/unknown.bin": 0]
        )
        let unknownURL = tempDir.appendingPathComponent("unknown.bin")
        let (progressStream, progressContinuation) = AsyncStream.makeStream(of: (Int64, Int64).self)
        try await unknownClient.downloadFile(share: "Media", path: "unknown.bin", to: unknownURL) { bytes, total in
            progressContinuation.yield((bytes, total))
            return true
        }
        progressContinuation.finish()

        #expect(try Data(contentsOf: unknownURL) == unknownPayload)
        let unknownRanges = await unknownClient.recordedRanges
        #expect(unknownRanges.map(\.offset) == [0, 1_048_576, 1_300_000])
        #expect(await unknownClient.readFileDataCallCount == 0)

        var progressEvents: [(Int64, Int64)] = []
        for await event in progressStream {
            progressEvents.append(event)
        }
        #expect(progressEvents.map(\.0) == [1_048_576, 1_300_000])
        #expect(progressEvents.allSatisfy { $0.1 == 0 })

        let directoryEntries = try FileManager.default.contentsOfDirectory(atPath: tempDir.path).sorted()
        #expect(directoryEntries == ["empty.bin", "unknown.bin"])
    }

    @Test("Default SMB download mid-transfer cancellation throws CancellationError and cleans up part files")
    func testDefaultSMBDownloadMidTransferCancellation() async throws {
        let payload = Data(repeating: 0x42, count: 2_200_000)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichierkit_dl_cancel_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let callbackDestURL = tempDir.appendingPathComponent("callback_cancelled.bin")
        let callbackClient = RangeOnlyMockSMBClient(files: ["Media/video.bin": payload])

        await #expect(throws: CancellationError.self) {
            try await callbackClient.downloadFile(share: "Media", path: "video.bin", to: callbackDestURL) { bytes, total in
                bytes < total && bytes <= 1_048_576 ? false : true
            }
        }
        #expect(!FileManager.default.fileExists(atPath: callbackDestURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: tempDir.path).isEmpty)
        #expect(await callbackClient.recordedRanges.count == 1)

        let (enteredSecondReadStream, enteredSecondReadContinuation) = AsyncStream.makeStream(of: Void.self)
        let taskClient = RangeOnlyMockSMBClient(
            files: ["Media/video.bin": payload],
            onRangeRead: { callIndex in
                if callIndex == 2 {
                    enteredSecondReadContinuation.yield()
                    try await Task.sleep(for: .seconds(5))
                }
            }
        )
        let taskDestURL = tempDir.appendingPathComponent("task_cancelled.bin")

        let downloadTask = Task {
            try await taskClient.downloadFile(share: "Media", path: "video.bin", to: taskDestURL)
        }

        for await _ in enteredSecondReadStream {
            break
        }
        downloadTask.cancel()

        await #expect(throws: CancellationError.self) {
            try await downloadTask.value
        }
        #expect(!FileManager.default.fileExists(atPath: taskDestURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: tempDir.path).isEmpty)
        #expect(await taskClient.recordedRanges.count == 2)
    }

    @Test("Default SMB download failure cleans up part files and preserves existing destination")
    func testDefaultSMBDownloadFailurePreservesExistingDestination() async throws {
        let payload = Data(repeating: 0x5A, count: 2_200_000)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichierkit_dl_fail_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let newDestURL = tempDir.appendingPathComponent("missing_after_error.bin")
        let failNewClient = RangeOnlyMockSMBClient(
            files: ["Media/video.bin": payload],
            failAfterReadCount: 1,
            errorToThrow: SMBError.timeout
        )

        await #expect(throws: SMBError.timeout) {
            try await failNewClient.downloadFile(share: "Media", path: "video.bin", to: newDestURL)
        }
        #expect(!FileManager.default.fileExists(atPath: newDestURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: tempDir.path).isEmpty)

        let existingDestURL = tempDir.appendingPathComponent("existing.bin")
        let originalData = Data("Original Intact File Contents".utf8)
        try originalData.write(to: existingDestURL)

        let failReplaceClient = RangeOnlyMockSMBClient(
            files: ["Media/video.bin": payload],
            failAfterReadCount: 1,
            errorToThrow: SMBError.timeout
        )

        await #expect(throws: SMBError.timeout) {
            try await failReplaceClient.downloadFile(share: "Media", path: "video.bin", to: existingDestURL)
        }
        #expect(try Data(contentsOf: existingDestURL) == originalData)
        #expect(try FileManager.default.contentsOfDirectory(atPath: tempDir.path) == ["existing.bin"])

        let succeedReplaceClient = RangeOnlyMockSMBClient(files: ["Media/video.bin": payload])
        try await succeedReplaceClient.downloadFile(share: "Media", path: "video.bin", to: existingDestURL)
        #expect(try Data(contentsOf: existingDestURL) == payload)
        #expect(try FileManager.default.contentsOfDirectory(atPath: tempDir.path) == ["existing.bin"])
    }

    @Test("Default SMB download known-size early EOF fails without installing truncated output")
    func testDefaultSMBDownloadKnownSizeEarlyEOFFails() async throws {
        let truncatedPayload = Data(repeating: 0xCD, count: 1_500_000)
        let client = RangeOnlyMockSMBClient(
            files: ["Media/truncated.bin": truncatedPayload],
            reportedSizes: ["Media/truncated.bin": 2_000_000]
        )

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichierkit_dl_eof_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let destURL = tempDir.appendingPathComponent("truncated.bin")
        await #expect(throws: SMBError.self) {
            try await client.downloadFile(share: "Media", path: "truncated.bin", to: destURL)
        }
        #expect(!FileManager.default.fileExists(atPath: destURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: tempDir.path).isEmpty)

        let existingURL = tempDir.appendingPathComponent("existing_before_eof.bin")
        let originalData = Data("Keep Existing On Early EOF".utf8)
        try originalData.write(to: existingURL)

        await #expect(throws: SMBError.self) {
            try await client.downloadFile(share: "Media", path: "truncated.bin", to: existingURL)
        }
        #expect(try Data(contentsOf: existingURL) == originalData)
        #expect(try FileManager.default.contentsOfDirectory(atPath: tempDir.path) == ["existing_before_eof.bin"])
    }

    @Test("Default SMB download cleans up when destination directory is unavailable")
    func testDefaultSMBDownloadUnavailableDestinationDirectory() async throws {
        let client = RangeOnlyMockSMBClient(files: ["Media/video.bin": Data("video".utf8)])
        let parentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fichierkit_dl_missing_parent_\(UUID().uuidString)", isDirectory: true)
        let destinationURL = parentURL.appendingPathComponent("video.bin")

        await #expect(throws: Error.self) {
            try await client.downloadFile(share: "Media", path: "video.bin", to: destinationURL)
        }

        #expect(!FileManager.default.fileExists(atPath: parentURL.path))
        #expect(!FileManager.default.fileExists(atPath: destinationURL.path))
    }

    @Test("Player engines clamp playbackRate and ignore non-finite values")
    @MainActor
    func testPlayerEnginesPlaybackRateClampingAndNonFiniteValues() {
        let avEngine = AVPlayerEngine()
        defer { avEngine.tearDown() }
        #expect(avEngine.playbackRate == 1.0)

        avEngine.playbackRate = 0.05
        #expect(avEngine.playbackRate == 0.25)
        #expect(avEngine.avPlayer.defaultRate == 0.25)

        avEngine.playbackRate = 8.0
        #expect(avEngine.playbackRate == 4.0)
        #expect(avEngine.avPlayer.defaultRate == 4.0)

        avEngine.playbackRate = 1.5
        #expect(avEngine.playbackRate == 1.5)
        #expect(avEngine.avPlayer.defaultRate == 1.5)

        avEngine.playbackRate = .nan
        #expect(avEngine.playbackRate == 1.5)
        #expect(avEngine.avPlayer.defaultRate == 1.5)

        avEngine.playbackRate = .infinity
        #expect(avEngine.playbackRate == 1.5)
        #expect(avEngine.avPlayer.defaultRate == 1.5)

        avEngine.playbackRate = -.infinity
        #expect(avEngine.playbackRate == 1.5)
        #expect(avEngine.avPlayer.defaultRate == 1.5)

        let vlcEngine = TVVLCPlayerEngine()
        defer { vlcEngine.tearDown() }
        #expect(vlcEngine.playbackRate == 1.0)

        vlcEngine.playbackRate = -1.0
        #expect(vlcEngine.playbackRate == 0.25)

        vlcEngine.playbackRate = 10.0
        #expect(vlcEngine.playbackRate == 4.0)

        vlcEngine.playbackRate = 1.75
        #expect(vlcEngine.playbackRate == 1.75)

        vlcEngine.playbackRate = .nan
        #expect(vlcEngine.playbackRate == 1.75)

        vlcEngine.playbackRate = .infinity
        #expect(vlcEngine.playbackRate == 1.75)

        vlcEngine.playbackRate = -.infinity
        #expect(vlcEngine.playbackRate == 1.75)
    }

    @Test("DefaultMediaSourceResolver.invalidateSource disconnects non-AMSMB2 SMBClientProtocol doubles")
    func testResolverInvalidateDisconnectsProtocolClient() async {
        let server = SavedSMBConnection(host: "192.168.1.99", username: "tester", lastConnected: Date())
        let mockClient = PagedMockSMBClient(mockShares: ["Media"])
        let source = SharesMediaSource(server: server, client: mockClient)

        let resolver = DefaultMediaSourceResolver()
        await resolver.register(source: source)
        #expect(await resolver.smbClient(for: server.id) != nil)

        await resolver.invalidateSource(id: server.id)
        #expect(await mockClient.disconnectCallCount == 1)

        // Second invalidation is a safe no-op without extra disconnects
        await resolver.invalidateSource(id: server.id)
        #expect(await mockClient.disconnectCallCount == 1)
    }

    @Test("SharesMediaSource cursor and sequential page fetching use listDirectoryPage without listDirectory")
    func testSharesMediaSourceCursorAndSequentialPaging() async throws {
        let server = SavedSMBConnection(host: "192.168.1.50", username: "kevin", lastConnected: Date())
        let folderItem = MediaSourceItem(
            id: "raw-dir",
            name: "Albums",
            path: "Media/Albums",
            type: .folder
        )
        let photoOne = MediaSourceItem(
            id: "raw-1",
            name: "IMG_1.jpg",
            path: "Media/IMG_1.jpg",
            type: .image,
            size: 512
        )
        let photoTwo = MediaSourceItem(
            id: "raw-2",
            name: "IMG_2.jpg",
            path: "Media/IMG_2.jpg",
            type: .image,
            size: 1024
        )
        let client = PagedMockSMBClient(
            mockShares: ["Media"],
            pagesByCursor: [
                PagedMockSMBClient.initialCursorKey: SMBDirectoryPage(
                    items: [folderItem, photoOne],
                    nextCursor: "opaque-cursor-1",
                    totalCount: 3
                ),
                "opaque-cursor-1": SMBDirectoryPage(
                    items: [photoTwo],
                    nextCursor: nil,
                    totalCount: 3
                )
            ]
        )
        let source = SharesMediaSource(server: server, client: client)
        let rootFolder = MediaSourceItem(
            id: "root",
            name: "Media",
            path: "Media",
            type: .folder,
            sourceID: server.id,
            smbShare: "Media",
            smbPath: ""
        )

        let page0 = try await source.fetchItems(in: rootFolder, sortBy: .name, order: .ascending, page: 0, pageSize: 2)
        #expect(page0.map(\.id) == ["raw-dir", "raw-1"])
        #expect(page0.allSatisfy { $0.sourceID == server.id && $0.smbShare == "Media" })

        let page1 = try await source.fetchItems(in: rootFolder, sortBy: .name, order: .ascending, page: 1, pageSize: 2)
        #expect(page1.map(\.id) == ["raw-2"])
        #expect(page1.first?.smbPath == "IMG_2.jpg")

        // Exhausted scope should short-circuit without hitting client again
        let page2 = try await source.fetchItems(in: rootFolder, sortBy: .name, order: .ascending, page: 2, pageSize: 2)
        #expect(page2.isEmpty)

        #expect(await client.listDirectoryCallCount == 0)
        let requests = await client.requestedPages
        #expect(requests.count == 2)
        #expect(requests[0].cursor == nil)
        #expect(requests[1].cursor == "opaque-cursor-1")

        // Direct cursor API preserves nextCursor & totalCount metadata
        let directPage = try await source.fetchDirectoryPage(
            in: rootFolder,
            sortBy: .name,
            order: .ascending,
            cursor: nil,
            pageSize: 2
        )
        #expect(directPage.nextCursor == "opaque-cursor-1")
        #expect(directPage.totalCount == 3)
        #expect(directPage.hasMore)
    }

    @Test("SharesMediaSource share enumeration slices deterministically without Int.max")
    func testSharesMediaSourceBoundedSharePagination() async throws {
        let server = SavedSMBConnection(host: "192.168.1.50", username: "kevin", lastConnected: Date())
        let client = MockSMBClient(mockShares: ["Share 10", "Zulu", "Share 2", "Alpha", "Share 1"])
        let source = SharesMediaSource(server: server, client: client)

        let page0 = try await source.fetchDirectoryPage(in: nil, sortBy: .name, order: .ascending, cursor: nil, pageSize: 2)
        #expect(page0.items.map(\.name) == ["Alpha", "Share 1"])
        #expect(page0.nextCursor == "2")
        #expect(page0.totalCount == 5)
        #expect(page0.hasMore)

        let page1 = try await source.fetchDirectoryPage(in: nil, sortBy: .name, order: .ascending, cursor: page0.nextCursor, pageSize: 2)
        #expect(page1.items.map(\.name) == ["Share 2", "Share 10"])
        #expect(page1.nextCursor == "4")
        #expect(page1.hasMore)

        let page2 = try await source.fetchDirectoryPage(in: nil, sortBy: .name, order: .ascending, cursor: page1.nextCursor, pageSize: 2)
        #expect(page2.items.map(\.name) == ["Zulu"])
        #expect(page2.nextCursor == nil)
        #expect(!page2.hasMore)
    }

    @Test("SMBClientProtocol default listDirectoryPage handles folder-first sorting, invalid cursors, and zero pageSize")
    func testDefaultListDirectoryPageEdgeCases() async throws {
        let items = [
            MediaSourceItem(id: "s1", name: "Large.mp4", path: "Media/Large.mp4", type: .video, size: 9000),
            MediaSourceItem(id: "s2", name: "Small.jpg", path: "Media/Small.jpg", type: .image, size: 100),
            MediaSourceItem(id: "dir", name: "ZFolder", path: "Media/ZFolder", type: .folder, size: 0)
        ]
        let client = MockSMBClient(mockShares: ["Media"], mockItems: items)

        let sizeDescPage = try await client.listDirectoryPage(
            share: "Media",
            path: "",
            cursor: nil,
            pageSize: 2,
            sortBy: .size,
            order: .descending
        )
        #expect(sizeDescPage.items.map(\.id) == ["dir", "s1"])
        #expect(sizeDescPage.nextCursor == "2")
        #expect(sizeDescPage.totalCount == 3)

        let invalidCursor = try await client.listDirectoryPage(
            share: "Media",
            path: "",
            cursor: "invalid",
            pageSize: 2,
            sortBy: .name,
            order: .ascending
        )
        #expect(invalidCursor.items.isEmpty)
        #expect(invalidCursor.nextCursor == nil)

        let zeroPageSize = try await client.listDirectoryPage(
            share: "Media",
            path: "",
            cursor: nil,
            pageSize: 0,
            sortBy: .name,
            order: .ascending
        )
        #expect(zeroPageSize.items.isEmpty)
        #expect(zeroPageSize.nextCursor == nil)
    }

    @Test("AMSMB2Client disconnect is idempotent even when called from a cancelled task")
    func testAMSMB2ClientDisconnectSafeFromCancelledTask() async {
        let server = SavedSMBConnection(host: "192.168.1.250", username: "guest", lastConnected: Date())
        let client = AMSMB2Client(server: server, password: "")

        let started = AsyncStream.makeStream(of: Void.self)
        let gate = AsyncStream.makeStream(of: Void.self)
        let cancelledTask = Task {
            started.continuation.yield()
            for await _ in gate.stream {
                break
            }
            #expect(Task.isCancelled)
            await client.disconnect()
        }
        for await _ in started.stream {
            break
        }
        cancelledTask.cancel()
        gate.continuation.finish()
        await cancelledTask.value
        await client.disconnect()
    }

    @Test("SharesMediaSource preserves cursor across failed or cancelled page retries and isolates scopes by folder and pageSize")
    func testSharesMediaSourceRetryAndScopeIsolation() async throws {
        let server = SavedSMBConnection(host: "192.168.1.50", username: "kevin", lastConnected: Date())
        let photoOne = MediaSourceItem(id: "p1", name: "IMG_1.jpg", path: "Media/A/IMG_1.jpg", type: .image, size: 100)
        let photoTwo = MediaSourceItem(id: "p2", name: "IMG_2.jpg", path: "Media/A/IMG_2.jpg", type: .image, size: 200)
        let photoB = MediaSourceItem(id: "pb", name: "IMG_B.jpg", path: "Media/B/IMG_B.jpg", type: .image, size: 300)

        let (enteredCancelStream, enteredCancelContinuation) = AsyncStream.makeStream(of: Void.self)
        let client = PagedMockSMBClient(
            mockShares: ["Media"],
            pagesByCursor: [
                PagedMockSMBClient.initialCursorKey: SMBDirectoryPage(
                    items: [photoOne],
                    nextCursor: "cursor-page-1",
                    totalCount: 2
                ),
                "cursor-page-1": SMBDirectoryPage(
                    items: [photoTwo],
                    nextCursor: nil,
                    totalCount: 2
                ),
                "folderB-cursor": SMBDirectoryPage(
                    items: [photoB],
                    nextCursor: nil,
                    totalCount: 2
                )
            ],
            onPageRequest: { callIndex, request in
                // Fail first attempt of page 1 (callIndex == 2) and stall/cancel second attempt (callIndex == 3)
                if callIndex == 2 {
                    #expect(request.cursor == "cursor-page-1")
                    throw SMBError.timeout
                }
                if callIndex == 3 {
                    #expect(request.cursor == "cursor-page-1")
                    enteredCancelContinuation.yield()
                    try await Task.sleep(for: .seconds(5))
                }
            }
        )
        let source = SharesMediaSource(server: server, client: client)
        let folderA = MediaSourceItem(
            id: "folderA",
            name: "A",
            path: "Media/A",
            type: .folder,
            sourceID: server.id,
            smbShare: "Media",
            smbPath: "A"
        )
        let folderB = MediaSourceItem(
            id: "folderB",
            name: "B",
            path: "Media/B",
            type: .folder,
            sourceID: server.id,
            smbShare: "Media",
            smbPath: "B"
        )

        let page0 = try await source.fetchItems(in: folderA, sortBy: .name, order: .ascending, page: 0, pageSize: 1)
        #expect(page0.map(\.id) == ["p1"])

        await #expect(throws: SMBError.timeout) {
            try await source.fetchItems(in: folderA, sortBy: .name, order: .ascending, page: 1, pageSize: 1)
        }

        let cancelTask = Task {
            try await source.fetchItems(in: folderA, sortBy: .name, order: .ascending, page: 1, pageSize: 1)
        }
        for await _ in enteredCancelStream {
            break
        }
        cancelTask.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await cancelTask.value
        }

        // Retrying page 1 after both error and cancellation must reuse the exact cursor recorded by page 0
        let retriedPage1 = try await source.fetchItems(in: folderA, sortBy: .name, order: .ascending, page: 1, pageSize: 1)
        #expect(retriedPage1.map(\.id) == ["p2"])

        // Different pageSize must be isolated into its own scope rather than hitting folderA's pageSize=1 exhaustion
        let differentPageSizePage2 = try await source.fetchItems(
            in: folderA,
            sortBy: .name,
            order: .ascending,
            page: 2,
            pageSize: 5
        )
        #expect(differentPageSizePage2.isEmpty)

        // Resetting folderB page 0 must not corrupt or reset folderA
        _ = try await source.fetchItems(in: folderB, sortBy: .name, order: .ascending, page: 0, pageSize: 1)
        let folderAPastEnd = try await source.fetchItems(in: folderA, sortBy: .name, order: .ascending, page: 2, pageSize: 1)
        #expect(folderAPastEnd.isEmpty)

        let requests = await client.requestedPages
        #expect(requests.count == 6)
        #expect(requests[0].cursor == nil)
        #expect(requests[1].cursor == "cursor-page-1")
        #expect(requests[2].cursor == "cursor-page-1")
        #expect(requests[3].cursor == "cursor-page-1")
        #expect(requests[4].cursor == "10")
        #expect(requests[5].path == "B")
    }
}
