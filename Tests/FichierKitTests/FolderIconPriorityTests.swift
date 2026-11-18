//
//  FolderIconPriorityTests.swift
//  FichierKitTests
//

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import FichierKit

@Suite("Folder Icon Priority & Caching Rules")
struct FolderIconPriorityTests {
    #if canImport(UIKit)
    private func createTestImage(size: CGSize, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func waitForIcon(
        manager: MediaCacheManager,
        folderPath: String,
        shareName: String,
        matchingSize: CGSize? = nil
    ) async -> UIImage? {
        for _ in 0..<40 {
            if let image = await manager.folderIcon(folderPath: folderPath, shareName: shareName) {
                if let matchingSize {
                    if image.size == matchingSize { return image }
                } else {
                    return image
                }
            }
            try? await Task.sleep(for: .milliseconds(15))
        }
        return nil
    }

    private func cleanup(manager: MediaCacheManager, shareName: String, folderPath: String) {
        let imgKey = manager.folderIconKey(shareName: shareName, folderPath: folderPath, isVideo: false)
        let vidKey = manager.folderIconKey(shareName: shareName, folderPath: folderPath, isVideo: true)
        let legacyKey = manager.legacyFolderIconKey(shareName: shareName, folderPath: folderPath)
        for key in [imgKey, vidKey, legacyKey] {
            let fileURL = manager.thumbnailsDirectory.appendingPathComponent("\(key).jpg")
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    @Test("Parent folder path calculation")
    func parentFolderPath() {
        #expect(MediaCacheManager.parentFolderPath(of: "movies/vacation/clip.mp4") == "movies/vacation")
        #expect(MediaCacheManager.parentFolderPath(of: "/photos/summer/pic.jpg") == "photos/summer")
        #expect(MediaCacheManager.parentFolderPath(of: "file.png") == "")
    }

    @Test("Image icon is strictly prioritized over video icon (video linked first)")
    func imagePriorityOverVideo() async {
        let manager = MediaCacheManager.shared
        let folderPath = "test_folder_\(UUID().uuidString)"
        let shareName = "TestShare"
        let childImagePath = "\(folderPath)/image.jpg"
        let childVideoPath = "\(folderPath)/video.mp4"

        defer { cleanup(manager: manager, shareName: shareName, folderPath: folderPath) }

        let videoSize = CGSize(width: 32, height: 32)
        let photoSize = CGSize(width: 48, height: 48)

        let videoImage = createTestImage(size: videoSize, color: .red)
        let photoImage = createTestImage(size: photoSize, color: .green)

        // 1. Link video first
        manager.linkFolderIcon(
            videoImage,
            childPath: childVideoPath,
            shareName: shareName,
            isVideo: true
        )

        let resolvedVideo = await waitForIcon(
            manager: manager,
            folderPath: folderPath,
            shareName: shareName,
            matchingSize: videoSize
        )
        #expect(resolvedVideo != nil)
        #expect(resolvedVideo?.size == videoSize)

        // 2. Link image later -> image must now take priority
        manager.linkFolderIcon(
            photoImage,
            childPath: childImagePath,
            shareName: shareName,
            isVideo: false
        )

        let resolvedWithImage = await waitForIcon(
            manager: manager,
            folderPath: folderPath,
            shareName: shareName,
            matchingSize: photoSize
        )
        #expect(resolvedWithImage != nil)
        #expect(resolvedWithImage?.size == photoSize)
    }

    @Test("Image icon retains priority when video is linked later")
    func imageRetainsPriorityOverSubsequentVideo() async {
        let manager = MediaCacheManager.shared
        let folderPath = "test_folder_rev_\(UUID().uuidString)"
        let shareName = "TestShare"
        let childImagePath = "\(folderPath)/image.jpg"
        let childVideoPath = "\(folderPath)/video.mp4"

        defer { cleanup(manager: manager, shareName: shareName, folderPath: folderPath) }

        let videoSize = CGSize(width: 32, height: 32)
        let photoSize = CGSize(width: 48, height: 48)

        let videoImage = createTestImage(size: videoSize, color: .red)
        let photoImage = createTestImage(size: photoSize, color: .green)

        // 1. Link image first
        manager.linkFolderIcon(
            photoImage,
            childPath: childImagePath,
            shareName: shareName,
            isVideo: false
        )

        let resolvedImage = await waitForIcon(
            manager: manager,
            folderPath: folderPath,
            shareName: shareName,
            matchingSize: photoSize
        )
        #expect(resolvedImage != nil)
        #expect(resolvedImage?.size == photoSize)

        // 2. Link video later -> photo must still be returned
        manager.linkFolderIcon(
            videoImage,
            childPath: childVideoPath,
            shareName: shareName,
            isVideo: true
        )

        // Short wait to ensure video write completes
        try? await Task.sleep(for: .milliseconds(50))

        let resolvedStillImage = await manager.folderIcon(folderPath: folderPath, shareName: shareName)
        #expect(resolvedStillImage != nil)
        #expect(resolvedStillImage?.size == photoSize)
    }

    @Test("MediaSourceItem correctly links image and video icons")
    func mediaSourceItemLinking() async {
        let folderPath = "travel_\(UUID().uuidString)"
        let manager = MediaCacheManager.shared
        defer { cleanup(manager: manager, shareName: "Media", folderPath: folderPath) }

        let imageItem = MediaSourceItem(
            id: "img1",
            name: "scenery.jpg",
            path: "\(folderPath)/scenery.jpg",
            type: .image,
            sourceID: "server1",
            smbShare: "Media",
            smbPath: "\(folderPath)/scenery.jpg"
        )

        let folderItem = MediaSourceItem(
            id: "folder1",
            name: "travel",
            path: folderPath,
            type: .folder,
            sourceID: "server1",
            smbShare: "Media",
            smbPath: folderPath
        )

        let testImg = createTestImage(size: CGSize(width: 40, height: 40), color: .yellow)
        imageItem.linkThumbnailAsFolderIcon(testImg)

        var loaded: UIImage?
        for _ in 0..<40 {
            if let img = await folderItem.linkedFolderIcon() {
                loaded = img
                break
            }
            try? await Task.sleep(for: .milliseconds(15))
        }

        #expect(loaded != nil)
        #expect(loaded?.size == CGSize(width: 40, height: 40))
    }
    #endif
}
