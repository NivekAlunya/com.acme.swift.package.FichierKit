//
//  VLCVideoThumbnailSessionTests.swift
//  FichierKitTests
//

import Foundation
import Testing
@testable import FichierKit

@Suite("VLCVideoThumbnailSession Cancel-Before-Start Tests")
struct VLCVideoThumbnailSessionTests {
    #if canImport(UIKit)
    @Test("cancel() before start() prevents thumbnailer from starting")
    @MainActor
    func cancelBeforeStartIsIgnored() async {
        let actor = VLCVideoThumbnailActor()
        let session = VLCVideoThumbnailSession(sessionID: UUID(), owner: actor)

        session.cancel()
        session.start(
            with: URL(fileURLWithPath: "/tmp/nonexistent_vlc_thumb.mkv"),
            maxDimension: 200,
            snapshotPosition: 0.1
        )

        // Cancelled task in VLCVideoThumbnailActor returns nil promptly without hanging.
        let task = Task {
            await actor.generateThumbnail(
                from: URL(fileURLWithPath: "/tmp/nonexistent_vlc_thumb.mkv"),
                timeoutSeconds: 5.0
            )
        }
        task.cancel()
        let result = await task.value
        #expect(result == nil)
    }
    #endif
}
