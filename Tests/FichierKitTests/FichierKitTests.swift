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
}
