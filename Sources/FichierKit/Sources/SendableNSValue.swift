//
//  SendableNSValue.swift
//  FichierKit
//

import Foundation

/// Wrapper around opaque `NSValue` dialog references passed by `VLCDialogProvider`.
///
/// Marked `@unchecked Sendable` as an immutable `let` wrapper around an opaque `NSValue` token passed to `@MainActor`.
struct SendableNSValue: @unchecked Sendable {
    let value: NSValue
}
