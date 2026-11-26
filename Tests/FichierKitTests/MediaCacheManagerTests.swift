//
//  MediaCacheManagerTests.swift
//  FichierKitTests
//

import Foundation
import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import FichierKit

@Suite("MediaCacheManager Tests")
struct MediaCacheManagerTests {
    @Test("cacheKey and videoKey are deterministic and scoped by connectionID")
    func keyGenerationIsDeterministicAndScoped() {
        let manager = MediaCacheManager()
        let keyA = manager.cacheKey(for: "Photos", path: "/2026/img.jpg", dimension: 420, connectionID: "conn-1")
        let keyB = manager.cacheKey(for: "Photos", path: "/2026/img.jpg", dimension: 420, connectionID: "conn-1")
        let keyOtherConn = manager.cacheKey(for: "Photos", path: "/2026/img.jpg", dimension: 420, connectionID: "conn-2")

        #expect(keyA == keyB)
        #expect(keyA != keyOtherConn)

        let videoA = manager.videoKey(for: "Movies", path: "/clip.mp4", connectionID: "conn-1")
        let videoB = manager.videoKey(for: "Movies", path: "/clip.mp4", connectionID: "conn-2")
        #expect(videoA != videoB)
    }

    #if canImport(UIKit)
    @Test("saveThumbnailAsync and getThumbnailAsync persist and retrieve thumbnail image")
    func saveAndLoadThumbnailAsync() async {
        let manager = MediaCacheManager()
        let key = "test-thumb-\(UUID().uuidString)"
        let targetURL = manager.thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        defer { try? FileManager.default.removeItem(at: targetURL) }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        await manager.saveThumbnailAsync(image, for: key)
        #expect(manager.hasThumbnail(for: key))

        let loaded = await manager.getThumbnailAsync(for: key)
        #expect(loaded != nil)
    }
    #endif
}
