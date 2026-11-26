//
//  SendablePiPWindowControllerBox.swift
//  FichierKit
//

#if canImport(VLCKit) && canImport(UIKit) && !os(watchOS)
import VLCKit

/// Wrapper bridging `VLCPictureInPictureWindowControlling` callbacks from VLCKit onto `@MainActor`.
///
/// Marked `@unchecked Sendable` as an immutable one-shot transport box; `controller` is only accessed on `@MainActor`.
struct SendablePiPWindowControllerBox: @unchecked Sendable {
    let controller: (any VLCPictureInPictureWindowControlling)?
}
#endif
