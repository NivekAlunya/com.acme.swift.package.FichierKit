//
//  VLCPictureInPictureTests.swift
//  FichierKitTests
//

import Foundation
import Testing
@testable import FichierKit
#if canImport(VLCKit)
import VLCKit
#endif

@Suite("VLC Picture-in-Picture Tests")
struct VLCPictureInPictureTests {
    #if canImport(VLCKit) && canImport(UIKit) && !os(watchOS)
    @Test("VLCPictureInPictureMediaController safely handles nil media player")
    func testMediaControllerWithoutPlayer() {
        let controller = VLCPictureInPictureMediaController(mediaPlayer: nil)

        #expect(controller.mediaLength() == 0)
        #expect(controller.mediaTime() == 0)
        #expect(controller.isMediaSeekable() == false)
        #expect(controller.isMediaPlaying() == false)

        var completionCalled = false
        controller.seek(by: 10_000) {
            completionCalled = true
        }
        #expect(completionCalled == true)
    }

    @Test("TVVLCPlayerEngine initializes PiP inactive and clears PiP callback on clearCallbacks")
    @MainActor
    func testEnginePiPLifecycleAndCallbackReset() {
        let engine = TVVLCPlayerEngine()
        defer { engine.tearDown() }

        #expect(engine.isPiPActive == false)
        #expect(engine.isPiPReady == false)

        var callbackInvoked = false
        engine.onPiPStatusChanged = { _ in
            callbackInvoked = true
        }
        engine.clearCallbacks()
        engine.onPiPStatusChanged?(true)
        #expect(callbackInvoked == false)

        engine.togglePiP()
        engine.startPiP()
        engine.stopPiP()
        engine.tearDown()
        #expect(engine.isPiPActive == false)
    }
    #endif
}
