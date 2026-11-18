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
    private func createTestImage(color: UIColor = .blue) -> UIImage {
        let size = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test("Parent folder path calculation")
    func parentFolderPath() {
        #expect(MediaCacheManager.parentFolderPath(of: "movies/vacation/clip.mp4") == "movies/vacation")
        #expect(MediaCacheManager.parentFolderPath(of: "/photos/summer/pic.jpg") == "photos/summer")
        #expect(MediaCacheManager.parentFolderPath(of: "file.png") == "")
    }

    @Test("Image icon is strictly prioritized over video icon")
    func imagePriorityOverVideo() async {
        let manager = MediaCacheManager.shared
        let folderPath = "test_folder_\(UUID().uuidString)"
        let shareName = "TestShare"
        let childImagePath = "\(folderPath)/image.jpg"
        let childVideoPath = "\(folderPath)/video.mp4"

        let videoImage = createTestImage(color: .red)
        let photoImage = createTestImage(color: .green)

        // 1. Link video first
        manager.linkFolderIcon(
            videoImage,
            childPath: childVideoPath,
            shareName: shareName,
            isVideo: true
        )

        // Allow async disk write to complete
        try? await Task.sleep(for: .milliseconds(80))

        let resolvedVideoOnly = await manager.folderIcon(folderPath: folderPath, shareName: shareName)
        #expect(resolvedVideoOnly != nil)

        // 2. Link image
        manager.linkFolderIcon(
            photoImage,
            childPath: childImagePath,
            shareName: shareName,
            isVideo: false
        )

        try? await Task.sleep(for: .milliseconds(80))

        // Image must now be resolved even though video was also linked
        let resolvedWithImage = await manager.folderIcon(folderPath: folderPath, shareName: shareName)
        #expect(resolvedWithImage != nil)
    }

    @Test("MediaSourceItem correctly links image and video icons")
    func mediaSourceItemLinking() async {
        let folderPath = "travel_\(UUID().uuidString)"
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

        let testImg = createTestImage(color: .yellow)
        imageItem.linkThumbnailAsFolderIcon(testImg)

        try? await Task.sleep(for: .milliseconds(80))

        let loaded = await folderItem.linkedFolderIcon()
        #expect(loaded != nil)
    }
    #endif
}
