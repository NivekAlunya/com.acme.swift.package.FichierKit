//
//  ThumbnailPrefetchCoordinatorTests.swift
//  FichierKitTests
//
//

import Foundation
import Testing
@testable import FichierKit

@Suite("ThumbnailPrefetchCoordinator")
struct ThumbnailPrefetchCoordinatorTests {

    @Test("Processes images before videos and skips folders")
    func prioritizesImagesBeforeVideosAndSkipsFolders() async {
        let coordinator = ThumbnailPrefetchCoordinator()
        let recorder = RecordedIDs()

        let items = [
            MediaSourceItem(id: "folder_1", name: "Folder", path: "/Folder", type: .folder),
            MediaSourceItem(id: "vid_1", name: "clip.mp4", path: "/clip.mp4", type: .video),
            MediaSourceItem(id: "img_1", name: "photo.jpg", path: "/photo.jpg", type: .image),
            MediaSourceItem(id: "img_2", name: "raw.dng", path: "/raw.dng", type: .image)
        ]

        await coordinator.schedulePrefetch(folderKey: "test_folder", items: items) { item in
            await recorder.append(item.id)
        }

        // Wait briefly for the utility task to drain all 3 non-folder items
        for _ in 0..<50 {
            if await recorder.count() == 3 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        let processed = await recorder.values()
        #expect(processed == ["img_1", "img_2", "vid_1"])
    }

    @Test("Waits while visible loads are active and resumes once idle")
    func gatesBehindVisibleLoads() async {
        let coordinator = ThumbnailPrefetchCoordinator()
        let recorder = RecordedIDs()

        await coordinator.beginVisibleLoad()
        let items = [
            MediaSourceItem(id: "img_1", name: "photo.jpg", path: "/photo.jpg", type: .image)
        ]

        await coordinator.schedulePrefetch(folderKey: "gated_folder", items: items) { item in
            await recorder.append(item.id)
        }

        try? await Task.sleep(for: .milliseconds(60))
        #expect(await recorder.count() == 0)

        await coordinator.endVisibleLoad()
        for _ in 0..<50 {
            if await recorder.count() == 1 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(await recorder.values() == ["img_1"])
    }
}

private actor RecordedIDs {
    private var ids: [String] = []

    func append(_ id: String) {
        ids.append(id)
    }

    func count() -> Int {
        ids.count
    }

    func values() -> [String] {
        ids
    }
}
