//
//  SendablePiPWindowControllerBox.swift
//  FichierKit
//

#if canImport(VLCKit) && canImport(UIKit) && !os(watchOS)
import VLCKit

/// Thread-safe wrapper bridging `VLCPictureInPictureWindowControlling` callbacks from VLCKit onto `@MainActor`.
struct SendablePiPWindowControllerBox: @unchecked Sendable {
    let controller: (any VLCPictureInPictureWindowControlling)?
}
#endif
