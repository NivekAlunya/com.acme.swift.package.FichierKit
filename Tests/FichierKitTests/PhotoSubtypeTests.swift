//
//  PhotoSubtypeTests.swift
//  FichierKitTests
//
//

import Testing
@testable import FichierKit

@Suite("PhotoSubtype")
struct PhotoSubtypeTests {

    @Test("Infers RAW subtype from camera RAW extensions")
    func infersRawFromExtensions() {
        for ext in ["dng", "DNG", ".cr3", "nef", "arw", "raf"] {
            #expect(PhotoSubtype.from(extension: ext) == .raw)
        }
    }

    @Test("Infers animated subtype from animated image extensions")
    func infersAnimatedFromExtensions() {
        for ext in ["gif", "GIF", "webp", "avif"] {
            #expect(PhotoSubtype.from(extension: ext) == .animated)
        }
    }

    @Test("Infers standard subtype for common raster extensions")
    func infersStandardForCommonExtensions() {
        for ext in ["jpg", "jpeg", "heic", "png", ""] {
            #expect(PhotoSubtype.from(extension: ext) == .standard)
        }
    }

    @Test("MediaFormatStyle uses PhotoSubtype badge label and symbol")
    func formatStyleUsesPhotoSubtype() {
        let liveItem = MediaSourceItem(
            id: "ph_1",
            name: "IMG_0001.HEIC",
            path: "ph_1",
            type: .image,
            photoSubtype: .livePhoto
        )
        let info = MediaFormatStyle.formatInfo(for: liveItem)
        #expect(info.label == "LIVE")
        #expect(info.pictogramName == "livephoto")
    }
}
