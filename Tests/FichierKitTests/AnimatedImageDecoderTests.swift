//
//  AnimatedImageDecoderTests.swift
//  FichierKitTests
//

#if canImport(UIKit)
import Foundation
import Testing
import UIKit
@testable import FichierKit

@Suite("AnimatedImageDecoder Tests")
struct AnimatedImageDecoderTests {

    @Test("Corrupt data returns nil or fallback")
    func testCorruptDataFallback() {
        let corruptData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let image = AnimatedImageDecoder.decode(from: corruptData)
        #expect(image == nil)
    }

    @Test("Empty data returns nil")
    func testEmptyData() {
        let emptyData = Data()
        let image = AnimatedImageDecoder.decode(from: emptyData)
        #expect(image == nil)
    }

    @Test("Valid animated GIF decodes into animated image with frames")
    func testValidAnimatedGIF() {
        // Minimal 2-frame 1x1 GIF89a with 100ms and 200ms delays
        let gifBytes: [UInt8] = [
            71, 73, 70, 56, 57, 97, 1, 0, 1, 0, 128, 0, 0, 0, 0, 0,
            255, 255, 255, 33, 249, 4, 0, 10, 0, 0, 0, 44, 0, 0, 0, 0,
            1, 0, 1, 0, 0, 2, 2, 68, 1, 0, 33, 249, 4, 0, 20, 0,
            0, 0, 44, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 68, 1,
            0, 59
        ]
        let gifData = Data(gifBytes)
        let image = AnimatedImageDecoder.decode(from: gifData)

        #expect(image != nil)
        if let image {
            #expect(image.images?.count == 2)
            #expect(image.duration >= 0.29 && image.duration <= 0.31)
        }
    }
}
#endif

