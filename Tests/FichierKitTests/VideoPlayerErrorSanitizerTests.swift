//
//  VideoPlayerErrorSanitizerTests.swift
//  FichierKitTests
//

import Testing
@testable import FichierKit

@Suite("VideoPlayerErrorSanitizer Tests")
struct VideoPlayerErrorSanitizerTests {
    @Test("Sanitizes IPv4 addresses and SMB credential URLs")
    func sanitizesIPsAndSMBURLs() {
        let raw = "Failed to open smb://alice:secret@192.168.1.42/Movies/clip.mkv from 10.0.0.5"
        let sanitized = VideoPlayerErrorSanitizer.sanitize(raw)

        #expect(!sanitized.contains("alice"))
        #expect(!sanitized.contains("secret"))
        #expect(!sanitized.contains("192.168.1.42"))
        #expect(!sanitized.contains("10.0.0.5"))
        #expect(sanitized.contains("smb://<server>/Movies/clip.mkv"))
        #expect(sanitized.contains("<host>"))
    }
}
