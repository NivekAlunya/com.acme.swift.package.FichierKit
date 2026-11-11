//
//  SendableNSValue.swift
//  FichierKit
//

import Foundation

/// Thread-safe wrapper around opaque `NSValue` dialog references passed by `VLCDialogProvider`.
struct SendableNSValue: @unchecked Sendable {
    let value: NSValue
}
