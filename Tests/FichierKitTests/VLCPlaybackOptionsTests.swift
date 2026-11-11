//
//  VLCPlaybackOptionsTests.swift
//  FichierKitTests
//
//

import Foundation
import Testing
@testable import FichierKit
#if canImport(VLCKit)
import VLCKit
#endif

@Suite("VLCPlaybackOptions & Direct SMB Playback Tests")
struct VLCPlaybackOptionsTests {
    @Test("Default options configure network-caching = 999, avcodec-skiploopfilter = 1, and clamp negative caching values")
    func testDefaultOptionsAndNonSMBDictionary() throws {
        let defaults = VLCPlaybackOptions()
        #expect(defaults.networkCachingMs == 999)
        #expect(defaults.skipLoopFilter == VLCPlaybackOptions.defaultSkipLoopFilter)
        #expect(defaults.username == nil)
        #expect(defaults.password == nil)
        #expect(defaults.domain == nil)

        let clamped = VLCPlaybackOptions(networkCachingMs: -250, skipLoopFilter: "  ")
        #expect(clamped.networkCachingMs == 0)
        #expect(clamped.skipLoopFilter == "1")

        let nilURLOptions = defaults.makeVLCMediaOptionsDictionary(for: nil)
        #expect(nilURLOptions["network-caching"] as? Int == 999)
        #expect(nilURLOptions["avcodec-skiploopfilter"] as? String == "1")
        #expect(nilURLOptions["subsdec-encoding"] as? String == "Windows-1252")
        #expect(nilURLOptions["demux"] == nil)
        #expect(nilURLOptions["smb-user"] == nil)
        #expect(nilURLOptions["smb-pwd"] == nil)
        #expect(nilURLOptions["smb-domain"] == nil)

        let fileURLOptions = defaults.makeVLCMediaOptionsDictionary(
            for: URL(fileURLWithPath: "/tmp/local_clip.mkv")
        )
        #expect(fileURLOptions["network-caching"] as? Int == 999)
        #expect(fileURLOptions["avcodec-skiploopfilter"] as? String == "1")
        #expect(fileURLOptions["subsdec-encoding"] as? String == "Windows-1252")
        #expect(fileURLOptions["demux"] as? String == "mkv_trusted")
        #expect(fileURLOptions["smb-user"] == nil)
        #expect(fileURLOptions["smb-pwd"] == nil)
        #expect(fileURLOptions["smb-domain"] == nil)
    }

    @Test("SMB URL and explicit credentials populate smb-user, smb-pwd, smb-domain, mkv_trusted, and skiploopfilter")
    func testSMBOptionDictionaryGeneration() throws {
        let smbURL = try #require(URL(string: "smb://nas.local/Media/Movies/film.mkv"))
        let defaultsForSMB = VLCPlaybackOptions().makeVLCMediaOptionsDictionary(for: smbURL)
        #expect(defaultsForSMB["network-caching"] as? Int == 999)
        #expect(defaultsForSMB["avcodec-skiploopfilter"] as? String == "1")
        #expect(defaultsForSMB["subsdec-encoding"] as? String == "Windows-1252")
        #expect(defaultsForSMB["demux"] as? String == "mkv_trusted")
        #expect(defaultsForSMB["smb-user"] as? String == "")
        #expect(defaultsForSMB["smb-pwd"] as? String == "")
        #expect(defaultsForSMB["smb-domain"] as? String == "WORKGROUP")

        let blankDomainOptions = VLCPlaybackOptions(
            username: "guest",
            password: "",
            domain: "   "
        ).makeVLCMediaOptionsDictionary(for: nil)
        #expect(blankDomainOptions["avcodec-skiploopfilter"] as? String == "1")
        #expect(blankDomainOptions["smb-user"] as? String == "guest")
        #expect(blankDomainOptions["smb-pwd"] as? String == "")
        #expect(blankDomainOptions["smb-domain"] as? String == "WORKGROUP")

        let customOptions = VLCPlaybackOptions(
            username: "alice",
            password: "p@ss#word",
            domain: "STUDIO",
            networkCachingMs: 1500,
            skipLoopFilter: "4"
        ).makeVLCMediaOptionsDictionary(for: smbURL)
        #expect(customOptions["network-caching"] as? Int == 1500)
        #expect(customOptions["avcodec-skiploopfilter"] as? String == "4")
        #expect(customOptions["smb-user"] as? String == "alice")
        #expect(customOptions["smb-pwd"] as? String == "p@ss#word")
        #expect(customOptions["smb-domain"] as? String == "STUDIO")
    }

    @Test("makeSMBURL encodes reserved characters, normalizes hosts/IPv6, and rejects invalid inputs")
    func testMakeSMBURLNormalizationAndEncoding() throws {
        let encoded = try #require(
            VLCPlaybackOptions.makeSMBURL(
                host: "  SMB://192.0.2.50%en0/  ",
                share: "/My Share/",
                relativePath: "/./Season #1/Épisode [01]?%.mkv"
            )
        )
        #expect(encoded.scheme == "smb")
        #expect(encoded.host == "192.0.2.50")
        #expect(encoded.path == "/My Share/Season #1/Épisode [01]?%.mkv")
        #expect(encoded.absoluteString.contains("%20"))
        #expect(encoded.absoluteString.contains("%23"))
        #expect(encoded.absoluteString.contains("%3F"))
        #expect(encoded.absoluteString.contains("%5B"))

        let ipv6Raw = try #require(
            VLCPlaybackOptions.makeSMBURL(
                host: "fe80::1%en0",
                share: "Media",
                relativePath: "video.mkv"
            )
        )
        #expect(ipv6Raw.absoluteString == "smb://[fe80::1]/Media/video.mkv")

        let ipv6Bracketed = try #require(
            VLCPlaybackOptions.makeSMBURL(
                host: "[fe80::2%en1]",
                port: 445,
                share: "Media",
                relativePath: "clip.mkv"
            )
        )
        #expect(ipv6Bracketed.absoluteString == "smb://[fe80::2]:445/Media/clip.mkv")

        let shareRoot = try #require(
            VLCPlaybackOptions.makeSMBURL(host: "nas.local", share: "Media", relativePath: "")
        )
        #expect(shareRoot.absoluteString == "smb://nas.local/Media")

        #expect(VLCPlaybackOptions.makeSMBURL(host: "", share: "Media", relativePath: "a.mkv") == nil)
        #expect(VLCPlaybackOptions.makeSMBURL(host: "192.0.2.50", share: "///", relativePath: "a.mkv") == nil)
        #expect(VLCPlaybackOptions.makeSMBURL(host: "192.0.2.50:445", share: "Media", relativePath: "a.mkv") == nil)
        #expect(VLCPlaybackOptions.makeSMBURL(host: "nas.local", port: 0, share: "Media") == nil)
        #expect(VLCPlaybackOptions.makeSMBURL(host: "nas.local", port: 70000, share: "Media") == nil)
    }

    @Test("TVVLCPlayerEngine load(url:startPosition:options:) applies caching and SMB options and cleans up on tearDown")
    @MainActor
    func testTVVLCPlayerEngineLoadAppliesOptionsAndTearsDown() throws {
        let engine = TVVLCPlayerEngine()
        defer { engine.tearDown() }

        let localURL = URL(fileURLWithPath: "/tmp/sample.mkv")
        engine.load(url: localURL)
        #expect(engine.lastLoadedURL == localURL)
        #expect(engine.appliedNetworkCachingMs == VLCPlaybackOptions.defaultNetworkCachingMs)
        #expect(
            engine.appliedMediaOptionKeys
                == ["avcodec-skiploopfilter", "demux", "network-caching", "subsdec-encoding"]
        )
        #if canImport(VLCKit)
        #expect(engine.mediaPlayer.media?.url == localURL)
        #endif

        let smbURL = try #require(
            VLCPlaybackOptions.makeSMBURL(
                host: "192.0.2.10",
                share: "Media",
                relativePath: "Movies/Sample Movie.mkv"
            )
        )
        let customOptions = VLCPlaybackOptions(
            username: "alice",
            password: "secret",
            domain: "HOME",
            networkCachingMs: 1200
        )
        engine.load(url: smbURL, startPosition: 42.5, options: customOptions)
        #expect(engine.lastLoadedURL == smbURL)
        #expect(engine.appliedNetworkCachingMs == 1200)
        #expect(
            engine.appliedMediaOptionKeys
                == [
                    "avcodec-skiploopfilter",
                    "demux",
                    "network-caching",
                    "smb-domain",
                    "smb-pwd",
                    "smb-user",
                    "subsdec-encoding"
                ]
        )
        #if canImport(VLCKit)
        #expect(engine.mediaPlayer.media?.url == smbURL)
        #endif

        engine.tearDown()
        #expect(engine.lastLoadedURL == nil)
        #expect(engine.appliedNetworkCachingMs == nil)
        #expect(engine.appliedMediaOptionKeys.isEmpty)
        #if canImport(VLCKit)
        #expect(engine.mediaPlayer.media == nil)
        #endif
    }
}
